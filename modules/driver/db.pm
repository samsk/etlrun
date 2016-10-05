# driver::db.pm
#
# Database manipulation module
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::db;

use strict;
use warnings;

use Encode qw(encode_utf8 decode_utf8 is_utf8);
use DBI qw(data_string_desc);
use Data::Dumper;
use XML::LibXML;
use Pg::hstore;	#FIXME: this should be optional load

#internal
use core;
use core::log;
use core::lru;
use core::xml;
use core::conf;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL, FEATURE: iterate
our $MODULE = 'db';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/dmlquery';

## RESULT NAMESPACE: $MODULE_RESULT, URL: $NAMESPACE_URL_RESULT
our $MODULE_RESULT = 'dbr';
our $NAMESPACE_URL_RESULT  = $NAMESPACE_URL . '/result';

my ($CACHE, %ITERATOR);
END { $CACHE = {}; undef $CACHE;
	%ITERATOR =(); undef %ITERATOR; }

## decode types
my @DECODE_TYPE = ('hstore', 'xml');

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# top child
	my $nod2 = $resp->createElementNS($NAMESPACE_URL_RESULT, $MODULE_RESULT . ':res');
	$nod->addChild($nod2);

	# copy idents
	my $name = core::xml::attrib($req, 'name', $NAMESPACE_URL);
	my $id = core::xml::attrib($req, 'id', $NAMESPACE_URL);
	$nod2->setAttribute('name', $name)
		if ($name);
	$nod2->setAttribute('id', $id)
		if ($id);

	# query
	my $ret = _dmlquery($reqid, $req, $nod2, \%params);
	if ($ret)
	{
		# attributes
		my $expires = core::conf::get('driver.db.response.cache');
		$nod->setAttributeNS(core::NAMESPACE_URL, core::ATTR_EXPIRES, time() + $expires)
			if (defined($expires));
	}
	return ($resp, core::CT_OK);
}

# _dmlquery($reqid, $req, $resp, $node)
sub _dmlquery($$$$)
{
	my ($reqid, $req, $resp, $params) = @_;

	## /dml/@user
	my $user = core::xml::attrib($req, 'user', $NAMESPACE_URL, '');
	## /dml/@password
	my $password = core::xml::attrib($req, 'password', $NAMESPACE_URL, '');

	# default DSN
	## /dml/@dsn
	my $dsn = core::xml::attrib($req, 'dsn', $NAMESPACE_URL);
	if (!$dsn) {
		$resp->addChild(core::raise_error($reqid, $MODULE, 400,
			_fatal => $resp,
			req => $req,
			msg => "BAD REQUEST: dsn connection string not defined"));
		return undef;
	}

	## /dml/@dsn == 'reuse'
	## /dml/@dsn == 'reuse:ID'
	if ($dsn =~ /^reuse(:([\w-]+))?$/o) {
		my $id = $2;

		my $key = 'driver.db.dsn';
		$key .= '.' . $id
			if ($id);

		$dsn = core::conf::get($key);
		if (!defined($dsn)) {
			$resp->addChild(core::raise_error($reqid, $MODULE, 412,
				_fatal => $resp,
				req => $req,
				msg => "PRECONDITION FAILED: no connection for reuse defined under config $key"));
			return undef;
		}
	}

	# cache connection
	my $db;
	my $ctx = core::lru::get($CACHE, $dsn);
	if (!defined($ctx))
	{
RECONNECT:
		# connect
		$db	= DBI->connect_cached('DBI:' . $dsn, $user, $password,
                       {	PrintError => 0,
				RaiseError => 0,
				AutoCommit => 1,
				pg_server_prepare => 1,
				pg_prepare_now => 1,
				pg_enable_utf8 => 1 });
		if (!defined($db))
		{
			$resp->addChild(core::raise_error($reqid, $MODULE, 500,
				_fatal => $resp,
				req => $req,
				msg => "database connection failed",
				error => $DBI::errstr,
				dsn => $dsn));
			return undef;
		}

		# cache connection
		$ctx = {
			'db'		=> $db,
			'dsn'		=> $dsn,
			'prepared'	=> {}
		};
		core::lru::set($CACHE, $dsn, $ctx, core::conf::get('driver.db.lru-size', 6),
				sub { $_[0]->{'db'}->disconnect()
					if ($_[0]->{'db'}); });
	}
	else
	{
		$db = $ctx->{'db'};
		if (!$db->ping())
		{
			core::log::PKG_MSG(LOG_WARNING, ": ping to database '%s' failed, reconnecting", $dsn);
			goto RECONNECT;
		}
	}

	# always set autocommit
	$db->{AutoCommit} = 1;

	# compile our program
	# FIXME: cache program to avoid recompilations (use @etl:uuid)
	my $program;
	if (!$params
		|| !exists($params->{-iterator}) || !defined($params->{-iterator})
		|| !exists($params->{-limit}) || !defined($params->{-limit})
		|| !exists($ITERATOR{$params->{-iterator}}))
	{
		$program = _compile($reqid, $ctx, $req, $resp, $params, undef) || return undef;
	}
	else
	{
		$program = $ITERATOR{$params->{-iterator}};
	}

	# execute program
	my $ret = _execute($reqid, $ctx, $program, $resp, $params);
	if ($ret && $params && exists($params->{-iterator}) && $params->{-iterator})
	{
		$ITERATOR{$params->{-iterator}} = $program;
		$resp->setAttributeNS(core::NAMESPACE_URL, core::ATTR_ITERATOR, $params->{-iterator});
	}
	return $ret;
}

# _get_param($node, $params, $params_out)
sub _get_params($$\@)
{
	my ($node, $params, $params_out) = @_;

	if ($node->hasChildNodes())
	{
		my $snode = $node->firstChild();
		while(defined($snode))
		{
			## /dml/execute/param
			if ($snode->nodeType() == XML_ELEMENT_NODE
				&& $snode->localName() eq 'param')
			{
				## /dml/execute/param/@c14n
				my $a_c14n = core::xml::attrib($snode, 'c14n', $NAMESPACE_URL);

				# get node content (if non-null)
				my $val;
				foreach my $n ($snode->nonBlankChildNodes())
				{
					my $text = $a_c14n ? $n->toStringC14N_v1_1() : $n->toString();

					if (defined($val))
					{	$val .= $text;	}
					else
					{	$val = $text;	}
				}

				# remove cdata subsections (to not pass it to db)
				#while($val	=~ s/\<\!\[CDATA\[(.+?)\]\]\>/$1/og) { 1; };

				## /dml/execute/param/@name
				my $a_name = core::xml::attrib($snode, 'name', $NAMESPACE_URL);

				## /dml/execute/param/@fetch
				my $a_fetch = core::xml::attrib($snode, 'fetch', $NAMESPACE_URL);

				## /dml/execute/param/@required
				my $a_require = core::xml::attrib($snode, 'required', $NAMESPACE_URL);

				## /dml/execute/param/@external
				my $a_external = core::xml::attrib($snode, 'external', $NAMESPACE_URL);

				# optionaly use passed param value, but only if param empty and
				# is not set as !external or is external
				$val = $params->{$a_name}
					if (($a_external || (!defined($a_external) && !defined($val)))
						&& defined($a_name) && exists($params->{$a_name}));

				# check if value set
				return (undef, "required parameter '$a_name' not set !")
					if ($a_require && !defined($val));

				# use complex val
				$val = {
					-fetch	=> $a_fetch,
					value	=> $val,
				} if ($a_fetch);

				# add to param list
				push(@$params_out, $val);
			}
			#next node
			$snode	= $snode->nextSibling();
		}
	}

	return 1;
}

# _compile($reqid, $ctx, $req, $resp, %params, $qnum);
sub _compile($$$$$\$%);
sub _compile($$$$$\$%)
{
	my ($reqid, $ctx, $req, $resp, $params, $qnum_in, %prepared) = @_;
	my (@program);

	## /dml/@xmlout = [0|1]
	my $glob_xmlout = (exists($prepared{-xmlout}) ? $prepared{-xmlout} :
				core::xml::attrib($req, [ 'xmlout', 'xml' ], $NAMESPACE_URL));
	$glob_xmlout = 1 if (!defined($glob_xmlout));
	$prepared{-xmlout} = $glob_xmlout;

	## /dml/@ignore
	my $glob_ignore = (exists($prepared{-ignore}) ? $prepared{-ignore} :
				core::xml::attrib($req, 'ignore', $NAMESPACE_URL));
	$prepared{-ignore} = $glob_ignore;

	# walk
	my $qnum = ($qnum_in ? $$qnum_in : 1);
	my $node = $req->firstChild();
	while(defined($node))
	{
		# skip non-interesting
		#	or not our namespace
		goto NEXT_NODE
			if ($node->nodeType() != XML_ELEMENT_NODE
				|| !$node->namespaceURI()
				|| $node->namespaceURI() ne $NAMESPACE_URL);

		# element name
		my $lname = $node->localName();

		# node specifics
		## /dml/@ignore
		my $msg_ignore	= core::xml::attrib($node, 'ignore', $NAMESPACE_URL);
		if (!$msg_ignore)
		{	$msg_ignore = $glob_ignore;			}
		else
		{	$msg_ignore = $msg_ignore . '|' . $glob_ignore;	}
		$msg_ignore = qr!$msg_ignore!im
			if ($msg_ignore);

		#transaction
		## /dml/transaction
		if ($lname eq 'transaction' && $node->hasChildNodes())
		{
			## /dml/transaction/@name
			my $name = core::xml::attrib($node, 'name', $NAMESPACE_URL) || 'tran_' . $qnum++;

			# prevent sub-transactions
			if (defined($qnum_in))
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 405,
					_fatal => $resp,
					req => $node,
					msg => "sub-transcations not allowed/supported"));
				return undef;
			}

			my $subprog = _compile($reqid, $ctx, $node, $resp, $params, $qnum, %prepared);
			if ($subprog && ref($subprog) eq 'ARRAY')
			{
				push(@program, {
					'op' => 'transaction',
					'name' => $name,
					'program' => $subprog
				});
			}
			else
			{	return $subprog;	}
		}
		## /dml/isolate
		elsif ($lname eq 'isolate' && $node->hasChildNodes())
		{
			## /dml/isolate/@name
			my $name = core::xml::attrib($node, 'name', $NAMESPACE_URL) || 'isol_' . $qnum++;

			my $subprog = &_compile($reqid, $ctx, $node, $resp, $params, undef, %prepared);
			if ($subprog && ref($subprog) eq 'ARRAY')
			{
				push(@program, {
					'op' => 'isolate',
					'name' => $name,
					'program' => $subprog,
				});
			}
			else
			{	return $subprog;	}
		}
		#prepare statment
		## /dml/prepare
		elsif ($lname eq 'prepare')
		{
			## /dml/prepare/@name
			my $name = core::xml::attrib($node, 'name', $NAMESPACE_URL);
			if (!defined($name) || $name eq '')
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					msg => "prepare statement has no name defined"));
				return undef;
			}
			if ($name !~ /^[\w_\/-]+$/o)
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					name => $name,
					msg => "prepare statement name should be a word or path"));
				return undef;
			}

			my $sql = core::xml::nodeValue($node);
			if (exists($prepared{$name}))
			{
				if ($prepared{$name}->{'sql'} ne $sql)
				{
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $node,
						name => $name,
						msg => "duplicate prepare statement name defined"));
					return undef;
				}

				# silently reuse
				goto NEXT_NODE;
			}
			if (!$node->hasChildNodes() || ($node->firstChild()->nodeType() != XML_TEXT_NODE
				&& $node->firstChild()->nodeType() != XML_CDATA_SECTION_NODE))
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					msg => "prepare statement text missing"));
				return undef;
			}

			## /dml/prepare/@once
			my $once = core::xml::attrib($node, 'once', $NAMESPACE_URL);

			## /dml/prepare/@ro
			my $ro = core::xml::attrib($node, 'ro', $NAMESPACE_URL);

			## /dml/prepare/@duplicate_params
			my $dup_params = core::xml::attrib($node, 'duplicate-params', $NAMESPACE_URL);

			## /dml/prepare/@returning
			my $returning = core::xml::attrib($node, 'returning', $NAMESPACE_URL);
			if ($returning) {
				if (!exists($prepared{$returning})) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $node,
						returning => $returning,
						msg => "statement given for returning not (yet) prepared"));
					return undef;
				}
				if (!$prepared{$returning}->{'ro'}) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $node,
						returning => $returning,
						msg => "statement given for returning is not defined as readonly (\@ro)"));
					return undef;
				}
			}

			## /dml/prepare/decode
			my %decode;
			my @decode_nodes = core::findnodes($node, $MODULE . ':decode', $MODULE => $NAMESPACE_URL);
			foreach my $nod (@decode_nodes) {
				my $field = core::xml::attrib($nod, 'field', $NAMESPACE_URL);
				if (!defined($field)) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $nod,
						msg => "decode without specified without field name (\@field)"));
					return undef;
				}
				if (exists($decode{$field})) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $nod,
						field => $field,
						msg => "multiple decode of one field not allowed"));
					return undef;
				}

				my $type = core::xml::attrib($nod, 'type', $NAMESPACE_URL);
				if (!defined($field)) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $nod,
						msg => "decode without specified without type (\@type)"));
					return undef;
				}

				if (!grep({ $_ eq lc($type) } @DECODE_TYPE)) {
					$resp->addChild(core::raise_error($reqid, $MODULE, 400,
						_fatal => $resp,
						req => $nod,
						type => $type,
						supported => \@DECODE_TYPE,
						msg => "decode type not (yet) supported"));
					return undef;
				}

				$decode{$field} = {
					'type' => lc($type),
				};
			}

			my $instr;
			push(@program, $instr = {
					'op' => 'prepare',
					'once' => $once,
					'ro' => $ro,
					'returning' => $returning,
					'duplicate' => $dup_params,
					'name' => $name,
					'sql' => $sql,
					'dsn' => $ctx->{'dsn'},
					'decode' => \%decode,
				});
			$prepared{$name} = $instr;
		}
		#execute prepare statement
		## /dml/execute
		elsif ($lname eq 'execute' || $lname eq 'exec')
		{
			## /dml/execute/@name
			my $name = core::xml::attrib($node, 'name', $NAMESPACE_URL);
			if (!defined($name) || $name eq '')
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					msg => "name of statement to execute is missing"));
				return undef;
			}
			if (!exists($prepared{$name}))
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					name => $name,
					msg => "prepare statement with given name does not exists"));
				return undef;
			}

			# count executions
			$prepared{$name}->{-execute}++;

			## /dml/execute/@id
			my $id	= core::xml::attrib($node, 'id', $NAMESPACE_URL);

			#get params
			my @pars;
			my ($ret, $err) = _get_params($node, $params, @pars);
			if (!$ret)
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 500,
					_fatal => $resp,
					req => $node,
					name => $name,
					error => $err,
					msg => "failed to collect parameters for execute"));
				return undef;
			}

			## /dml/execute/@once
			my $once = core::xml::attrib($node, 'once', $NAMESPACE_URL);

			## /dml/execute/@xml = [1|0]
			my $xmlout = core::xml::attrib($node, 'xml', $NAMESPACE_URL);

			## /dml/execute/@debug = [1|0]
			my $debug = core::xml::attrib($node, 'debug', $NAMESPACE_URL);

			## /dml/execute/@store
			my $store = core::xml::attrib($node, 'store', $NAMESPACE_URL);

			# do not combine
			if ($xmlout && $store)
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 500,
					_fatal => $resp,
					req => $node,
					name => $name,
					msg => "xmlout and store attributes can not be combined"));
				return undef;
			}

			push(@program, {
					'op' => 'execute',
					'name' => $name,
					'id' => $id,
					'once' => $once,
					'ignore' => $msg_ignore,
					'params' => (@pars ? \@pars : undef),
					'xmlout' => (defined($xmlout) ? ($xmlout || ($glob_xmlout && $xmlout != 0)) : $glob_xmlout),
					'store'  => $store,
					'debug' => $debug,
					'prepare' => $prepared{$name},
					'returning' => defined($prepared{$name}->{'returning'}) ? $prepared{$prepared{$name}->{'returning'}} : undef,
					'decode' => defined($prepared{$name}->{'decode'}) ? $prepared{$name}->{'decode'} : undef,
					'duplicate' => $prepared{$name}->{'duplicate'},
				});
		}
		#query statment
		## /dml/query
		elsif ($lname eq 'query')
		{
			if (!$node->hasChildNodes() || ($node->firstChild()->nodeType() != XML_TEXT_NODE
					&& $node->firstChild()->nodeType() != XML_CDATA_SECTION_NODE)) #is_text
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $node,
					msg => "query statement text missing"));
				return undef;
			}

			#prepare
			## /dml/query/@name
			my $name = core::xml::attrib($node, 'name', $NAMESPACE_URL) || $qnum++;
			## /dml/query/@id
			my $id	= core::xml::attrib($node, 'id', $NAMESPACE_URL);
			my $value = core::xml::nodeValue($node);

			#get params
			my @pars;
			my ($ret, $err) = _get_params($node, $params, @pars);
			if (!$ret)
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 500,
					_fatal => $resp,
					req => $node,
					name => $name,
					error => $err,
					msg => "failed to collect parameters for query"));
				return undef;
			}

			## /dml/query/@xml = [1|0]
			my $xmlout = core::xml::attrib($node, 'xml', $NAMESPACE_URL);

			## /dml/execute/@store
			my $store = core::xml::attrib($node, 'store', $NAMESPACE_URL);

			# do not combine
			if ($xmlout && $store)
			{
				$resp->addChild(core::raise_error($reqid, $MODULE, 500,
					_fatal => $resp,
					req => $node,
					name => $name,
					msg => "xmlout and store attributes can not be combined"));
				return undef;
			}

			push(@program, {
					'op' => 'query',
					'name' => $name,
					'id' => $id,
					'params' => (@pars ? \@pars : undef),
					'sql' => $value,
					'xmlout' => (defined($xmlout) ? ($xmlout || ($glob_xmlout && $xmlout != 0)) : $glob_xmlout),
				});
		}

NEXT_NODE:
		# next elem
		$node = $node->nextSibling();
	}

	# return
	$$qnum_in = $qnum
		if ($qnum_in);
	return \@program;
}

sub _xmlreply_decode($$) {
	my ($decode, $val) = @_;
	my $type = $decode->{'type'};

	if ($type =~ /^(pg:)?hstore$/o) {
		$val = Pg::hstore::decode($val);
	} elsif ($type eq 'xml') {
		my $doc = eval { core::xml::parse($val); };

		if ($doc) {
			$val = $doc->documentElement();
		}
	}
	return $val;
}

sub _xmlreply_value($$$$$) {
	my ($resp, $node, $name, $value, $decode) = @_;

	$value = _xmlreply_decode($decode->{$name}, $value)
		if ($decode && exists($decode->{$name}));

	my $r = ref($value);
	if (!$r) {
		my $node2 = $resp->ownerDocument()->createElement($name);

		if (defined($value) && $value ne '') {
			if (!core::xml::needsCDATA($value)) {
				$node2->appendText($value);
			} else {
				$node2->addChild(new XML::LibXML::CDATASection($value));
			}	
		}
		$node->addChild($node2);
	} elsif ($r eq 'ARRAY') {
		foreach my $val (@$value) {
			&_xmlreply_value($resp, $node, $name, $val);
		} 
	} elsif ($r eq 'HASH') {
		my $node2 = $resp->ownerDocument()->createElement($name);

		foreach my $key (keys(%$value)) {
			&_xmlreply_value($resp, $node2, $key, $value->{$key});
		}
		$node->addChild($node2);
	} elsif (core::xml::isXML($value)) {
		my $node2 = $resp->ownerDocument()->createElement($name);

		$node2->addChild($value);
		$node->addChild($node2);
	}

	return 1;
}

sub _xmlreply($$$$$$;$)
{
	my ($resp, $dbh, $res, $decode, $name, $params, $id) = @_;

	# limit support
	my $limit;
	$limit = $params->{-limit}
		if ($params && $params->{-limit});

	# get row names
	my $fields = $res->{NUM_OF_FIELDS} || 0;
	my $cols = $res->{NAME_lc};

	for(my $i = 0; $i < $fields; $i++) {
		$$cols[$i] =~ s/[^\w]/_/og;
	}

	# fetch data
	my $recnum = 0;
	while((my $arr = $res->fetchrow_arrayref()) && (!$limit || $recnum < $limit))
	{
		$recnum++;

		my $node = $resp->ownerDocument()->createElementNS($NAMESPACE_URL_RESULT, $MODULE_RESULT . ':r');
		$node->setAttribute('n', $name);
		$node->setAttribute('id', $id)
			if (defined($id));

		for(my $i = 0; $i < $fields; $i++) {
			_xmlreply_value($resp, $node, $$cols[$i], $$arr[$i], $decode);
		}
		$resp->addChild($node);
	}

	# was not a select or result is empty
	if ($recnum == 0 && defined($recnum = $res->rows()) && $recnum >= 0)
	{
		my $node = $resp->ownerDocument()->createElementNS($NAMESPACE_URL_RESULT, $MODULE_RESULT . ':IUD');
		$node->setAttribute('n', $name);
		$node->setAttribute('id', $id)
			if (defined($id));
		$node->appendText($recnum);
		$resp->addChild($node);
	}
	# was statement with ignored error (like duplicate insert or similar)
	elsif ($recnum < 0 && $dbh->errstr)
	{
		my $node = $resp->ownerDocument()->createElementNS($NAMESPACE_URL_RESULT, $MODULE_RESULT . ':IUD');
		$node->setAttribute('n', $name);
		$node->setAttribute('id', $id)
			if (defined($id));
		$node->appendText(-1);
		$resp->addChild($node);
	}
	elsif ($recnum < 0)
	{
		warn "FIXME: producing incorrect response";
		my $node = $resp->ownerDocument()->createElementNS($NAMESPACE_URL_RESULT, $MODULE_RESULT . ':ERROR');
		$node->setAttribute('n', $name);
		$node->setAttribute('id', $id)
			if (defined($id));
		$node->appendText($res->errstr);
		$resp->addChild($node);
	}

	# next iteration needed
	if ($limit)
	{
		$params->{-iterator} = $name . '_' . ($id || time())
			if (!defined($params->{-iterator}));
		if ($recnum < $limit)
		{
			$params->{-iterator} = undef;
			return 1;
		}
		return 2;	# ongoing
	}

	# $resp->addChild( new XML::LibXML::Comment( " " . $recnum . " RECORDS [" . $name . "]" ) );
	return 1;
}

sub _storevar($$$$\%$)
{
	my ($dbh, $res, $name, $id, $opts, $varname) = @_;

	my $hash = $res->fetchrow_hashref();
	$hash->{-name} = $res->{NAME_lc};

	$opts->{'-vars'}->{$varname} = $hash;
	return (keys(%$hash) > 1);
}

sub _build_params($\%)
{
	my ($params, $opts) = @_;

	return () if (!defined($params));
	return @$params if (!grep({ ref() } @$params));

	my @pars;
	foreach my $par (@$params)
	{
		push(@pars, $par), next
			if (!ref($par));

		goto DEF_VALUE
			if (!defined($opts) || !%$opts);

		# fetch variable by name.property
		if (exists($par->{-fetch}) && exists($opts->{'-vars'}))
		{
			my ($name, $prop) = split(/\./o, $par->{-fetch}, 2);
			my $vars = $opts->{'-vars'};

			goto DEF_VALUE
				if (!exists($vars->{$name}) || !defined($vars->{$name}));

			my $var = $vars->{$name};
			my @keys = @{ $var->{-name} };

			# no property - use first from variable
			$prop = $keys[0]
				if (!defined($prop) || $prop eq '');

			# lowercase match
			($prop) = grep({ lc($prop) eq lc($_) } keys(%$var));

			goto DEF_VALUE
				if (!defined($prop));

			push(@pars, $var->{$prop});
			next;
		}

DEF_VALUE:
		push(@pars, $par->{'value'})
	}
	return @pars;
}

sub _execute($$$$$%);
sub _execute_it($$$$$%)
{
	my ($reqid, $ctx, $program, $resp, $params, %opts) = @_;
	my $dbh = $ctx->{'db'};

	for(my $v_ii = 0; $v_ii <= $#$program; $v_ii++)
	{
		my $instr = $$program[$v_ii];

		my $op = $instr->{'op'};
		if ($op eq 'transaction')
		{
			my $name = $instr->{'name'};

			if (!$dbh->begin_work())
			{
				return (undef, core::raise_error($reqid, $MODULE, 500,
					#_fatal => $resp,
					instr => $instr,
					error => $dbh->errstr,
					msg => "failed to start transaction"));
			}

			if (_execute($reqid, $ctx, $instr->{'program'}, $resp, $params, isolate => 1, %opts)
				&& !core::conf::get('driver.db.nocommit', 0))
			{
				if (!$dbh->commit())
				{
					return (undef, core::raise_error($reqid, $MODULE, 500,
						#_fatal => $resp,
						instr => $instr,
						error => $dbh->errstr,
						msg => "failed to commit transaction"));
				}
			}
			else
			{
				core::conf::log(1, "nocommit mode - rolling back transaction '%s'", $name)
					if (core::conf::get('driver.db.nocommit', 0));
				if (!$dbh->rollback())
				{
					return (undef, core::raise_error($reqid, $MODULE, 500,
						#_fatal => $resp,
						instr => $instr,
						error => $dbh->errstr,
						msg => "failed to rollback transaction"));
				}
			}
		}
		elsif ($op eq 'isolate')
		{
			_execute($reqid, $ctx, $instr->{'program'}, $resp, $params, isolate => 1, %opts);
		}
		elsif ($op eq 'prepare')
		{
			next if ($params->{-iterator});

			my $name = $instr->{'name'};
			my $sql = $instr->{'sql'};
			my $csth = \$ctx->{'prepare'}->{$sql}->{$name};

			# prepare stmt if not alread cached
			if (!$$csth || $$csth->{-active})
			{
				core::log::PKG_MSG(LOG_NOTICE, " - preparing '%s'", $name);

				# NOTE: prepare si also critical operation, but it wont fail (DBI problem) !
				$instr->{-sth} = eval { $dbh->prepare($sql) };
				if (!$instr->{-sth})
				{
					return (undef, core::raise_error($reqid, $MODULE, 500,
						#_fatal => $resp,
						instr => $instr,
						error => $dbh->errstr,
						sql => $sql,
						msg => "failed to prepare given SQL statement"));
				}

				# cache sth
				$$csth = { -sth => $instr->{-sth},
					   -active => 0 }
					   if (!$$csth);
			}
			else
			{
				core::log::PKG_MSG(LOG_INFO, " preparing '%s' (cached)", $name);

				# use cached sth
				$instr->{-sth} = $$csth->{-sth};
			}
			$instr->{-csth} = $$csth;
		}
		elsif ($op eq 'execute')
		{
			my $name = $instr->{'name'};
			my $id = $instr->{'id'};
			my $once = $instr->{'once'} || $instr->{'prepare'}->{'once'};
			my $ignore = $instr->{'ignore'};
			my $xmlout = $instr->{'xmlout'};
			my $store = $instr->{'store'};
			my $sth = $instr->{'prepare'}->{-sth};
			my $csth = $instr->{'prepare'}->{-csth};
			my $debug = $instr->{'debug'};
			my $returning = $instr->{'returning'};
			my $duplicate = $instr->{'duplicate'};
			my $decode= $instr->{'decode'};

			# check once
			next
				if ($once && $csth->{-done});

			# build pars
			my (@pars, @pars2);
			@pars = @pars2 = _build_params($instr->{'params'}, %opts);
			@pars = (@pars, @pars)
				if ($duplicate);

			core::log::PKG_MSG(LOG_INFO, " - executing '%s' %s" . ($debug ? " %s" : ''),
				$name, $id || '', ($debug ? Dumper(\@pars) : ''));

			my $ret = 1;
			if (!$params->{-iterator}
				&& !$sth->execute(@pars)
				&& (!defined($ignore) || $sth->errstr !~ /$ignore/))
			{
				return (undef, core::raise_error($reqid, $MODULE, 500,
						#_fatal => $resp,
						instr => $instr,
						error => $dbh->errstr,
						name => $name,
						id => $id,
						values => \@pars,
						params => $params,
						msg => "failed to execute prepared statement"));
			}
			elsif ($store)
			{
				# doesn't works with iterator
				$csth->{-active} = 0;
				my $got = _storevar($dbh, $sth, $name, $id, %opts, $store);

				# need to return smth
				if (!$got && $returning) {
					core::log::PKG_MSG(LOG_DETAIL, " - executing returning '%s' %s" . ($debug ? " %s" : ''),
						$name, $id || '', ($debug ? Dumper(\@pars2) : ''));

					$returning->{-sth}->execute(@pars2);
					_storevar($dbh, $returning->{-sth}, $name, $id, %opts, $store);
				}
				$ret = 1;
			}
			elsif ($xmlout)
			{
				$csth->{-active} = 1;
				$ret = (_xmlreply($resp, $dbh, $sth, $decode, $name, $params, $id) == 1);
			}

			# release sth
			$sth->finish(), $csth->{-active} = 0, $csth->{-done} = 1
					if ($ret);
		}
		elsif ($op eq 'query')
		{
			next if ($params->{-iterator});

			die("NOT-YET-IMPLEMENTED");
		}
		else
		{
			die("[programming error] op '$op' not (yet) supported");
		}
	}

	return $resp;
}

sub _execute($$$$$%)
{
	my ($reqid, $ctx, $program, $resp, $params, %opts) = @_;

	my ($ret, $err) = _execute_it($reqid, $ctx, $program, $resp, $params, %opts);
	if (!defined($ret))
	{
		if (exists($opts{'isolate'}) && $opts{'isolate'})
		{
			$err->setNamespace($NAMESPACE_URL_RESULT, $MODULE_RESULT)
				if (!core::conf::get('driver.db.isolate.nomask', 0));
			if (!core::conf::get('driver.db.isolate.verbose', 0)
				&& core::log::level() < LOG_NOTICE)
			{
				# reduce information set
				my %allowed = ( 'name' => undef, 'error' => undef, 'id' => undef );
				foreach my $child ($err->nonBlankChildNodes())
				{
					if (!exists($allowed{$child->localName()})) {
						$child->unbindNode();
					} else {
						$child->setAttribute('isolated', 1);
					}
						
				}
			}
			$resp->addChild($err);
		}
		else
		{
			$resp->addChild($err);
			$resp->setAttributeNS(core::NAMESPACE_URL, core::ATTR_NOCACHE, 1);
		}
	}
	return $ret;
}

1;
