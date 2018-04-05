# core::kernel.pm
#
# Processing kernel - core component.
#
# Every request is forwarded to kernel, which will process it, if there
#	is a driver to handle given XML namespace. Response to driver is
#	converted to XML as needed and cached if possible.
#	Response will be automaticaly reprocesessed as needed till kernel
#	knows how to do it.
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::kernel;

use strict;
use warnings;

use Encode qw(encode_utf8 is_utf8);
#use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use XML::LibXML qw(:all);

# internal
use core;
use core::log;
use core::boot;
use core::xml;
use core::url;
use core::cache;
use core::auto;
use core::conf;
use core::time;
use core::txlog;
use core::convert;

my $SCHEMA_MAP;
my $SCHEMA_MAP_load = 0;

END { $SCHEMA_MAP = {}; undef $SCHEMA_MAP; }

# process($reqid, $doc, $req, %params): mixed
sub process($$$%);
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;

	# trace
	core::log::SYS_CALL("%s, <DOC>, <REQ>", $reqid);
	core::trace::req($reqid, $req, 'kernel-in');
	core::trace::req2(LOG_INFO, $reqid, \%params, 'kernel-params');

	# txlog recovery
	my ($resp, $txlog_lsn);
	$txlog_lsn = core::txlog::newLSN($reqid);
	return $resp
		if (defined($txlog_lsn)
			&& core::conf::get('core.txlog.recovery', 0)
			&& ($resp = core::txlog::fetch($reqid, $txlog_lsn, $req)));

	# params
	my ($driver, @postproc, $drv, $cache, $cache_id);
	## KERNEL -cache	-- cache time specification
	$cache = $params{-cache};
	## KERNEL -cache_id	-- manuall cache id
	$cache_id = $params{-cache_id};
	## KERNEL -norefetch	-- prevent resp. refetching
	my $norefetch = (exists($params{-norefetch}) && $params{-norefetch});
	## KERNEL -loopback	-- loop request back, after executing it
	my $loopback = (exists($params{-loopback}) && $params{-loopback});
	## KERNEL -noconvert	-- prevent automatic format conversion
	my $noconvert = (exists($params{-noconvert}) && $params{-noconvert});
	## KERNEL -forcetype	-- force driver result content type
	my $forcetype = $params{-forcetype};
	## KERNEL -postprocess	-- execute req via given postprocessor
	my $postproc = $params{-postprocess};

	# find default driver
	$driver = core::conf::get('core.driver.default', 'file');

	my $is_xml_req = core::xml::isXML($req) ? 1 : 0;

	# postprocessing needed
	if ($postproc && $is_xml_req)
	{
		$driver = $postproc;
	}
	# parse url if it is not a reference
	elsif (!$is_xml_req)
	{
		# parse
		$req = core::url::parse($req);

		# postprocess
		@postproc = split(/\+/o, $req->{schema});
		if (@postproc)
		{
			$driver	= shift(@postproc);
			$req->{href} =~ s/^\Q$req->{schema}\E/$driver/;
			$req->{schema} = $driver;
		}
		# our driver selector
		else {
			$driver = $req->{schema};
		}

		# allow url cache
		if (!defined($cache_id)
			&& !core::conf::in_array('core.cache.nocache', $driver, ['file'])) {
			$cache_id = $req->{href};
		} else {
			$cache_id = 0;
		}

		# try to find other driver
		$driver = $$drv[0]->{driver}
			if (($drv = _find_driver($driver)));
	}
	# we take only child of document root child (presuming this is master envelop) and try to
	#  find driver for given namespace, if no driver found we return the req back
	elsif (!(defined($driver = $req->namespaceURI())
		&& (defined($drv = _find_driver($driver)))))
	{
		core::log::SUB_MSG(LOG_WARNING, " - no driver found for '%s'", $driver)
			if (defined($driver));
		return undef;
	}
	else
	{
		## @etl:noexec
		if (core::get_attrib($req, core::ATTR_NOEXEC))
		{
			my ($res, $nod) = core::create_response($reqid, __PACKAGE__);
			core::xml::copyNode($nod, $req);
			return $res;
		}

		## @etl:loopback
		$loopback = $loopback || core::get_attrib($req, core::ATTR_LOOPBACK);
		## @etl:noconvert
		$noconvert = $noconvert || core::get_attrib($req, core::ATTR_NOCONVERT);
		## @etl:forcetype
		$forcetype = $forcetype || core::get_attrib($req, core::ATTR_FORCE_CTYPE);
		## @etl:driver
		$driver = core::get_attrib($req, core::ATTR_DRIVER);
		# prepend driver base if not rooted
		$driver = $$drv[0]->{driver} . '::' . $driver
			if ($driver && $driver !~ s/^:://o
				&& ($drv = _find_driver($req->namespaceURI())));

		# use discovered driver
		$driver = $$drv[0]->{driver}
			if (defined($drv) && !defined($driver));

		## @etl:cache
		$cache	= $cache || core::get_attrib($req, core::ATTR_CACHE);
		## @etl:cache_id
		$cache_id = $cache_id || core::get_attrib($req, core::ATTR_CACHE_ID)
				|| $req->toString();
	}

	# assign new driver
	my $namespace = $$drv[0]->{namespace};

	## KERNEL -driver
	$driver = exists($params{-driver}) ? $params{-driver} : $driver;

	# completize cache id
	my ($ct, $cache_key);
	my $curr_time = core::time::now();

	# try to fetch from cache
	if ($cache_id && !core::conf::get('core.cache.disable', 0))
	{
		$cache_key = sha1_hex(encode_utf8($cache_id));

		# load from cache allowing expiration
		my $data = core::cache::fetch($cache_key, $curr_time)
			if (!core::conf::get('core.cache.nofetch', 0));

		if (defined($data))
		{
			my $err;

			core::log::PKG_MSG(LOG_WARNING, " - got cached data (driver: %s)", $driver);
			($resp, $err) = core::xml::parse($$data);
			if ($resp)
			{
				$resp->setEncoding('utf-8');

				# trace
				core::trace::req($reqid, $resp, 'kernel-cached:' . $driver);
				goto DONE;
			}
			core::log::PKG_MSG(LOG_FATAL, " - failed to process cached data (%s)", $err);
			core::cache::invalidate($cache_key);
		}
	}
	$cache_id = undef;

	# trace
	core::log::PKG_MSG(LOG_WARNING, " - processing with %s", $driver);

	# try load
	if (!defined($driver) || !core::auto::load('driver::' . $driver))
	{
		# error response must be encapsulated
		my $nod;
		($resp, $nod) = core::create_response($reqid, __PACKAGE__);
		$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				req => $req,
				msg => 'BAD DRIVER: driver could not be loaded',
				namespace => $namespace,
				driver_is_empty => defined($driver),
				driver => $driver));
		return $resp;
	}

	# save attachments (we dont pass them to driver, because driver should not process it)
	## //etl:attachment
	my @attach;
	if ($is_xml_req)
	{
		my @nodes = core::findnodes($req, '//' . core::NAMESPACE . ':attachment');
		foreach my $nod (@nodes)
		{
			push(@attach, { s => $nod, p => $nod->parentNode() });
			$nod->unbindNode();
		}
	}

	# trace
	core::trace::req($reqid, $req, 'kernel-driver-in:' . $driver);

	# save request ID
	my $id = (($is_xml_req) ? core::get_attrib($req, core::ATTR_ID) : undef) || undef;

	# process by driver now
	{
		local $@;
		my $fn = $postproc ? "::postprocess" : "::process";
		my $handle = "driver::" . ${driver} . $fn;

		core::log::PKG_MSG(LOG_NOTICE, " - call %s(doc, <REQ>, <PARAMS>)", $handle);

		core::trace::step($reqid, 'kernel-driver:' . $driver);
		($resp, $ct) = eval { no strict 'refs'; &$handle($reqid, $doc, $req, %params) };
		core::trace::back($reqid);

		if (!defined($resp))
		{
			# error response must be encapsulated
			my $nod;
			($resp, $nod) = core::create_response($reqid, __PACKAGE__);
			$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				req => $req,
				error => $@,
				msg => 'BAD DRIVER: driver returned undefined response',
				namespace => $namespace,
				driver => $driver));
			return $resp;
		}
	}

	# no complex response
	return undef
		if (!$loopback && $resp eq core::RESPONSE_NULL);

	# force contenty type
	$ct = $forcetype
		if (defined($forcetype));

	# trace driver result
	core::trace::req2(LOG_DETAIL, $reqid, $resp, 'driver-out');

	# convert (if needed)
	$resp = core::convert::apply($reqid, $resp, $ct)
		if (!$noconvert &&
			(defined($ct) && $ct ne core::CT_OK && $ct ne core::CT_ERROR));

	# response node
	my $resp_node_ori = my $resp_node = $resp;
	$resp_node_ori = $resp_node = $resp->documentElement()
		if (core::xml::isDocument($resp_node));

	# attach ID back (to envelope, and to response node - because envelope might get removed)
	if (defined($id))
	{
		core::set_attrib($resp_node, core::ATTR_ID, $id);
		core::set_attrib($resp_node->firstChild(), core::ATTR_ID, $id)
			if ($resp_node->firstChild()
				&& $resp_node->firstChild()->nodeType() == XML_ELEMENT_NODE);
	}

	# non-loopback mode
	if (!$loopback)
	{
		# trace
		core::trace::req($reqid, $resp, 'kernel-driver-out:' . $driver);

		# add attachments back now
		if ($resp_node->firstChild()) {
			foreach (@attach) {
				$resp_node->firstChild()->appendChild($_->{s});
			}
		}
	}
	# check for possible exception response
	elsif (!$resp_node->isSameNode($resp))
	{
		my $req_node = $req;
		$req_node = $req->documentElement()
			if (core::xml::isDocument($req_node));

		# add attachments back now (to same parents)
		foreach (@attach) {
			$_->{p}->appendChild($_->{s});
		}

		# remove reponse childs
		foreach ($resp_node->childNodes()) {
			$_->unbindNode();
		}

		# copy response to request (XXX: should we clone it ?)
		$resp_node->appendChild($req_node);
		core::set_attrib($req_node, core::ATTR_NOREFETCH, 1);

		# trace
		core::trace::req($reqid, $resp, 'kernel-loopback:' . $driver);

		# prevent refetch loop
		$norefetch = 1;
	}
	else {
		die(__PACKAGE__ . ": can not use loopback !");
	}
	@attach = (); undef @attach;

	# suggest namespace & try refetch
	if (!$norefetch)
	{
		# backup resp
		my $resp_ori = $resp;

		# need namespace
		goto REFETCH_SKIP
			if (!defined($resp_node)
				|| !defined($resp_node->namespaceURI())
				|| !defined($resp_node->firstChild()));

		# norefetch attrib on envelope
		## @etl:norefetch
		goto REFETCH_SKIP
			if (core::get_attrib($resp_node, core::ATTR_NOREFETCH));

		# remove envelope
		$resp_node	= $resp_node->firstChild();
		while (defined($resp_node) && $resp_node->nodeType() != XML_ELEMENT_NODE) {
			$resp_node = $resp_node->nextSibling();
		}

		# norefetch attrib on data
		goto REFETCH_SKIP
			if (!defined($resp_node)
				|| !defined($resp_node->namespaceURI())
				|| core::get_attrib($resp_node, core::ATTR_NOREFETCH));

		# check if is node, and there is no other node sibling
		goto REFETCH_SKIP
			if (!$resp_node
				|| ($resp_node->nextSibling()
					&& $resp_node->nextSibling()->nodeType() == XML_ELEMENT_NODE));

		# force namespace (for hinting)
		# FIXME: not working as expected !!!! - what did I mean ?-)
		$resp_node->setNamespace($namespace)
				if (defined($namespace));

		# trace
		core::log::PKG_MSG(LOG_WARNING, " - reprocessing '%s'",
					$resp_node->namespaceURI() || $resp_node->nodeName());

		# refetch
		core::trace::step($reqid, 'kernel:refetch');
		core::trace::req($reqid, $resp_node, 'kernel-refetch');
		$resp = process($reqid, $resp, $resp_node, %params);
		core::trace::back($reqid);

		# not to reprocess
		if (!defined($resp))
		{
			core::log::PKG_MSG(LOG_WARNING, " - no result from reprocessing");
			$resp = $resp_ori;
		}
		else
		{	$resp_ori->unbindNode();
			undef $resp_ori;
			goto REFETCH_DONE;
		}

REFETCH_SKIP:
		# nothing to do here
	}
REFETCH_DONE:

	# cache response (if not disabled, or this is a error response)
	## etl:nocache		-- prevent response to be cached
	_cache_response($cache_key, $cache, $resp, $curr_time)
		if ($cache_key && $resp_node
			&& !core::conf::get('core.cache.nostore', 0)
			&& !core::get_attrib($resp_node, core::ATTR_NOCACHE));

DONE:
	# post-processes
	my $pproc_id = $driver;
	my $pdoc = $resp;
	foreach my $pproc (@postproc)
	{
		my $pdoc_node = $pdoc->documentElement();

		$pproc_id .= '+' . $pproc;

		core::trace::step($reqid, 'kernel:postprocess');
		core::trace::req($reqid, $pdoc_node, 'kernel-postprocess:' . $pproc);
		$pdoc = process($reqid, $pdoc, $pdoc_node, %params,
			-postprocess => $pproc, -cache_id => $pproc_id, -norefetch => 1);
		core::trace::back($reqid);
	}
	$resp = $pdoc;

	# txlog store
	core::txlog::store($reqid, $txlog_lsn, $req, $resp)
		if (defined($txlog_lsn));

	# finito
	core::trace::req($reqid, $resp, 'kernel-out');
	return $resp;
}

sub _load_schema_map()
{
	my @files = core::conf::file('driver.map') || die("$0: file(s) not found 'driver.map'\n");

	my %map;
	$SCHEMA_MAP_load = time();
	foreach my $f (@files) {
		my $fd;
		open($fd, $f) || next;

		my $l;
		while (($l = <$fd>))
		{
			chomp($l);
			next if ($l =~ /^\#/o || $l =~ /^\s*$/o);
			$l =~ s/(^\s+|\s+$)//og;
			my @m = split(/\s+/o, $l);
			push(@{$map{ $m[0] }}, { driver => $m[1], namespace => $m[2] });
		}
		close($fd);
	}
	$SCHEMA_MAP = \%map;
	return keys(%map) ? 1 : 0;
}

sub _find_driver($)
{
	my ($selector) = @_;

	# load schema map
	_load_schema_map()
		if (!$SCHEMA_MAP_load || $SCHEMA_MAP_load < core::conf::FLAG_RELOAD_TIME());

	# quick find schema
	return $SCHEMA_MAP->{ $selector }
		if (exists($SCHEMA_MAP->{ $selector }) && defined($SCHEMA_MAP->{ $selector }));

	# slow find schema
	# TODO !
	return undef;
}

sub _cache_response($$$$)
{
	my ($cache_key, $cache, $resp, $curr_time) = @_;

	$resp = $resp->documentElement()
		if (core::xml::isDocument($resp));

	# response expiration timestamp
	## @etl:ets	- expiration time stamp
	my $cache_ets = core::get_attrib($resp, core::ATTR_EXPIRES);

	# check user enforced caching definition
	if (defined($cache) || $cache || ($cache = core::conf::get('core.cache.force', 0)))
	{
		my ($ets, $err) = core::time::parse_offset($cache);
		return _error("failed to setup cache ($err)")
			if (defined($err));

		# cache if:
		#	- no response expiration set
		#	- cache is pre-expired (90 secs for net time diff)
		#	- response expiration is smaller than user expiration
		$cache_ets = $ets + $curr_time
			if ($ets && (!$cache_ets
					|| ($cache_ets < ($curr_time + 90))
					|| ($cache_ets < ($ets + $curr_time))));
	}

	# we have cache expiration timestamp
	if ($cache_ets)
	{
		## etl:ts	- time stamp
		my $cache_ts  = core::get_attrib($resp, core::ATTR_TIMESTAMP, -1);

		# save data with cached attr set & remove it for actual flow
		core::set_attrib($resp, core::ATTR_IS_CACHED, 1);
		my $data = $resp->toString();
		core::del_attrib($resp, core::ATTR_IS_CACHED);

		core::log::PKG_MSG(LOG_INFO, " - storing cache data %s", $cache_key);
		core::cache::store($cache_key, \$data, $cache_ets, $cache_ts);
	}
	return $cache_ets;
}

1;
