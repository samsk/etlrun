# driver::http.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::http;

use strict;
use warnings;

use Encode;
use Data::Dumper;
use XML::LibXML;
use HTTP::Date qw(time2str str2time);

# internal
use core;
use core::log;
use core::conf;
use core::xml;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'http';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/http';

our $CONF = {
	plugin		=> core::conf::get('driver.http.plugin', 'lwp'),
	agent		=> core::conf::get('driver.http.agent', 'Mozilla/5.0 (compatible;) Firefox/ETL'),
	redirs		=> core::conf::get('driver.http.redirs', 5),
	timeout		=> core::conf::get('driver.http.timeout', 15),
	force_post	=> 0,
	redir_post	=> core::conf::get('driver.http.redir-post', 0),
	cookie_jar	=> core::conf::get('tmp.path', '/tmp') . '/etl_cookies.' . $$ . '.txt',
	langs		=> core::conf::get('driver.http.langs', 'en-US,en'),
	retries		=> core::conf::get('driver.http.retries', 3),
	http_proxy	=> core::conf::get('driver.http.http-proxy', core::conf::get('driver.http.http_proxy')),
	keep_alive	=> core::conf::get('driver.http.keep-alive', 1),
	accept		=> core::conf::get('driver.http.accept', 'text/html,text/xml,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'),
	encoding	=> 'utf-8'
};

# _parse_req($reqid, $req)
sub _parse_req($$)
{
	my ($reqid, $req) = @_;

	# root node check
	## /request
	return (undef, "root node name must be 'req'")
		if ($req->localName() !~ /^req(uest)?$/o);

	# findout method
	## /request/@method = [get|post]
	my $method = core::xml::attrib($req, 'method', $NAMESPACE_URL);
	return (undef, "Unsupported method '$method' specified")
		if (defined($method) && $method !~ /^get|post$/o);

	# redir POST ?
	## /request/@redir-POST
	my $redirPOST = core::xml::attrib($req, [ 'redir-post', 'redir-POST' ], $NAMESPACE_URL);

	# parse url(s)
	my (@url, @get_params, @post_params, $node, @nodes);

	## /request/url
	@nodes = core::findnodes($req, $MODULE . ':url', $MODULE => $NAMESPACE_URL);
	foreach my $n (@nodes) {
		push(@url, core::xml::nodeValue($n));
	}

	# check
	return (undef, "<url> must be defined")
		if ($#url < 0);

	# parse params
	## /request/param
	@nodes = core::findnodes($req, $MODULE . ':param', $MODULE => $NAMESPACE_URL);
	foreach my $n (@nodes)
	{
		## /request/param/@name
		my $name = core::xml::attrib($n, 'name', $NAMESPACE_URL);

		return (undef, "Param must have a name attribute")
			if (!defined($name) || $name eq '');

		## /request/param/@method = [get|post]
		my $pmethod = core::xml::attrib($n, 'method', $NAMESPACE_URL) || $method;

		# check
		return (undef, "Unsupported method '$method' specified for param")
			if (defined($pmethod) && $pmethod !~ /^get|post$/o);

		# get value and add to param list (params are defined as 'post' if no req/param method specified)
		if (!defined($pmethod) || $pmethod eq 'post')
		{	push(@post_params, { name => $name, value => core::xml::nodeValue($n) });	}
		elsif ($pmethod eq 'get')
		{	push(@get_params, { name => $name, value => core::xml::nodeValue($n) });	}
	}

	# parse headers
	my %headers;
	## /request/header
	@nodes = core::findnodes($req, $MODULE . ':header', $MODULE => $NAMESPACE_URL);
	foreach my $n (@nodes)
	{
		## /request/header/@name
		my $name = core::xml::attrib($n, 'name', $NAMESPACE_URL);

		return (undef, "Header must have a name attribute")
			if (!defined($name) || $name eq '');

		$headers{ $name } = core::xml::nodeValue($n);
	}

	my %params;
	$params{'method'} = $method
		if ($method);
	$params{'get_params'} = \@get_params
		if (@get_params);
	$params{'post_params'} = \@post_params
		if (@post_params);
	$params{'headers'} = \%headers
		if (%headers);
	$params{'redir_post'} = $redirPOST
		if (defined($redirPOST));
	return ($url[0], \%params);
}

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# get url
	my ($url, $req_params, $id);
	if (ref($req) eq 'url')
	{	$url = $req->{href};	}
	else
	{
		## /request/@id
		$id = core::xml::attrib($req, 'id', $NAMESPACE_URL);

		($url, $req_params) = _parse_req($reqid, $req);
		# FIXME: not handling errors
		die($req_params . ': ' . $req->toString())
			if (!defined($url));
	}

	core::log::SYS_RESOURCE(" - retrieving url '%s'", $url);

	# retreive via our plugin
	# FIXME: not parsing params from $req !!
	my ($plugin, $res) = ($CONF->{'plugin'});
	if (!core::auto::load(__PACKAGE__ . '::' . $plugin)) {
		die("FATAL: failed to load plugin '$plugin'");
	}
	else
	{
		my $fn = sprintf(__PACKAGE__ . '::%s::retrieve', $plugin);
		my @pars = (\%params, $CONF);

		# join with req params
		@pars = ($req_params, @pars)
			if (defined($req_params));
		core::log::PKG_MSG(LOG_DETAIL, " - call %s(%s, %s, %d)", $fn, $CONF, $url, $#pars);

		no strict 'refs';
		$res = &$fn($CONF, $url, @pars);
	}

	# our response
	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# try open
	if (!defined($res->{code}) || ($res->{code} != 200 && $res->{code} != 302))
	{
		core::log::PKG_MSG(LOG_WARNING, " fetching '%s' failed with code %d", $url, $res->{code});
		$nod->addChild(core::raise_error($reqid, $MODULE, $res->{code},
			id => $id,
			req => $req,
			url => $url,
			msg => $res->{status},
			content => exists($res->{content}) ? $res->{content} : '-NOT-DECODEABLE-YET-'));
		return ($resp, core::CT_ERROR);
	}

	# try to use xml
	if (exists($res->{content}) && defined($res->{content}))
	{
		core::add_data_content($nod, $res->{content}, encode => $res->{content_binary},
				uri => $url);
	}
	else
	{
		core::log::PKG_MSG(LOG_FATAL, " no content found while fetching '%s' [programming error]", $url);
		$nod->addChild(core::raise_error($reqid, $MODULE, $res->{code},
			id => $id,
			req => $req,
			url => $url,
			msg => $res->{status},
			content => exists($res->{content}) ? 1 : 0,
			binary => exists($res->{content_binary}) ? 1 : 0));
		return ($resp, core::CT_ERROR);
	}

	# attributes
	core::set_attrib($nod, core::ATTR_SOURCE, $url);
	my $expires = $res->{expires} || (time() + core::conf::get('driver.http.response.cache'));
	core::set_attrib($nod, core::ATTR_TIMESTAMP, $res->{timestamp})
		if (defined($res->{timestamp}));
	core::set_attrib($nod, core::ATTR_EXPIRES, $expires)
		if (defined($expires));
	core::set_attrib($nod, core::ATTR_CONTENT_TYPE, $res->{'content-type'});
	core::set_attrib($nod, core::ATTR_NOREFETCH, '1');
	core::set_uri($resp, $url);

	# fini
	$res = $res->{'content-type'};
	return ($resp, $res);
}

1;
