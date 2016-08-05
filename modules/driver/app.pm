# driver::app.pm
#  -- application
#
# Copyright: Samuel Behan (c) 2012-2016
#
package driver::app;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::xml;
use core::url;
use core::conf;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'app';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/app';

sub _config($$)
{
	my ($reqid, $req) = @_;
	my (%params, @nodes);

	## app:config/conf
	@nodes = core::findnodes($req, 'conf');
	foreach my $node (@nodes) {
		## app:config/conf/@name
		my $name = core::xml::attrib($node, 'name', undef);
		## app:config/conf/@force
		my $force = core::xml::attrib($node, 'force', undef);

		die(__PACKAGE__ . " - no attribute \@name on conf definition")
			if (!defined($name) || $name eq '');

		core::conf::set($name, core::xml::nodeValue($node))
			if ($force || !defined(core::conf::get($name)));
	}

	## app:config/var
	@nodes = core::findnodes($req, 'var');
	foreach my $node (@nodes) {
		## app:config/var/@name
		my $name = core::xml::attrib($node, 'name', undef);

		die(__PACKAGE__ . " - no attribute \@name on var definition")
			if (!defined($name) || $name eq '');

		die(__PACKAGE__ . " - var \@name should be a word not '$name'")
			if ($name !~ /^[\w-]+$/o);

		my $elem = core::xml::getFirstElementChild($node);
		if ($elem) {
			$params{ $name } = $elem->cloneNode(1);
		} else {
			$params{ $name } = core::xml::nodeValue($node);
		}
	}

	return %params;
}

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my $help = exists($params{'help'}) ? ($params{'help'} || 1) : undef;
	
	## app:config
	my %config_params;
	my $config_node = core::findnodes($req, 'app:config', $MODULE => $NAMESPACE_URL);
	if ($config_node) {
		my %p = _config($reqid, $config_node);
		%config_params = (%config_params, %p);
	}
	
	## app:config-url
	my (@config_url_nodes) = core::findnodes($req, 'app:config-url', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@config_url_nodes) {
		my $url;

		## app:config-url/@optional
		my $optional = core::xml::attrib($nod, 'optional', $NAMESPACE_URL, 0);


		## app:config-url/@inject
		my $inject = core::xml::attrib($nod, 'inject', $NAMESPACE_URL);
		if ($inject && exists($params{$inject}) && $params{$inject}) {
			$url = $params{$inject};
		} else {
			$url = core::xml::nodeValue($nod);
		}

		core::log::PKG_MSG(LOG_NOTICE, " - loading config-url '%s' (optional: %s)", $url, $optional);

		my $resp = core::kernel::process($reqid, $doc, $url, %params);

		my $resp2;
		if ($resp && $resp->documentElement()) {
			my $err = core::get_error($resp);

			if ($err) {
				if (!$optional) {
					my ($resp, $nod) = core::create_response($reqid, $MODULE);
					$resp->addChild(core::raise_error($reqid, $MODULE, 500,
						_fatal => $resp,
						err => $err,
						msg => "config-url processing failed"));
					return ($resp, core::CT_ERROR);
				} else {
					next;
				}
			}

			$resp2 = $resp->documentElement()->firstChild();
		}
	
		if ($resp2) {
			my %p = _config($reqid, $resp2);
			%config_params = (%config_params, %p);
		}
	}

	# merge params
	%params = (%config_params, %params)
		if (keys(%config_params));

	## app:file-path
	my @data_nodes = core::findnodes($req, 'app:file-path', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@data_nodes) {
		core::conf::data_path(core::xml::nodeValue($nod));
	}

	## app:url[1]		- request url path
	my ($url, $app_req) = core::findnodes($req, 'app:url[1]', $MODULE => $NAMESPACE_URL);

	if (defined($url) && core::xml::nodeValue($url))
	{
		$app_req = core::kernel::process($reqid, $doc, core::xml::nodeValue($url), -norefetch=>1);


		$app_req = $app_req->documentElement()->firstChild()
			if ($app_req && $app_req->documentElement());
	}
	else
	{
		## app:req
		($app_req) = core::findnodes($req, 'app:req[1]/*[1]', $MODULE => $NAMESPACE_URL);
	}

	# FIXME: not raising exception as we should !!!
	die(__PACKAGE__ . " - no or invalid request/url defined !")
		if (!defined($url) && !defined($app_req));

	## app:conf[1]		- app configuration
	my @conf_nodes = core::findnodes($req, 'app:conf', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@conf_nodes)
	{
		## app:conf/@name
		my $name = core::xml::attrib($nod, 'name', $NAMESPACE_URL);

		# FIXME: not raising exception as we should !!!
		die(__PACKAGE__ . " - no attribute \@name on conf definition")
			if (!defined($name) || $name eq '');

		core::conf::set($name, core::xml::nodeValue($nod));
	}

	# find arguments definition
	my %args;
	## app:arg[1]		- app argument definition
	my @arg_nodes = core::findnodes($req, 'app:arg', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@arg_nodes)
	{

		## app:arg/@name
		my $name = core::xml::attrib($nod, 'name', $NAMESPACE_URL);
		## app:arg/@desc
		my $desc = core::xml::attrib($nod, 'desc', $NAMESPACE_URL);
		## app:arg/@default
		my $def = core::xml::attrib($nod, 'default', $NAMESPACE_URL);

		# FIXME: not raising exception as we should !!!
		die(__PACKAGE__ . " - no attribute \@name on arg definition")
			if (!defined($name) || $name eq '');
		die(__PACKAGE__ . " - duplicate argument '$name' !")
			if (exists($args{ $name }));

		# add
		$args{ $name } = { def => $def };
	}

	# check for help
	if ($help) {
		die("HELP NOT IMPLEMENTED");
	}

	# app-params
	my %app_params = %params;

	# find injection points & process them
	## app:req//@app:injection	- value injection marker
	my @injections = core::findnodes($app_req, '//*[@app:inject]', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@injections)
	{
		my $names = $nod->getAttributeNS($NAMESPACE_URL, 'inject');

		foreach my $name (split(/\s*,\s*/o, $names))
		{
			my $aname = (substr($name, 0, 1) eq '@') ? substr($name, 1) : undef;

			# append mode
			my ($is_append, $is_replace);
			if ($name =~ s/^([-+])//o || (defined($aname) && $aname =~ s/^([-+])//o)) {
				$is_append = ($1 eq '+');
				$is_replace = ($1 eq '-');
			}

			# defined as attribute
			if (defined($aname) && (exists($args{ $aname }) || exists($params{ $aname })))
			{
				my $val = exists($params{ $aname }) ? $params{ $aname } : $args{ $aname }->{def};
				if (!$is_append)
				{	$nod->setAttribute($aname, defined($val) ? $val : '');	}
				else
				{
					my $oldval = $nod->getAttribute($aname);
					$nod->setAttribute($aname, defined($val) ? ($oldval . $val) : '');	
				}
				delete($app_params{ $aname });
			}
			# check if defined as value
			elsif (exists($args{ $name }) || exists($params{ $name }))
			{
				# remove current child nodes
				if (!$is_append) {
					foreach my $child ($nod->childNodes()) {
						$nod->removeChild($child);
					}
				}

				# get value
				my $val = exists($params{ $name }) ? $params{ $name } : $args{ $name }->{def};

				# create node
				my $nod2;
				if (core::xml::isElement($val)) {
					$nod2 = $val;
				} else {
					$nod2 = $nod->ownerDocument->createTextNode(defined($val) ? $val : '');
				}
				
				# replace ?
				if ($is_replace) {
					$nod->replaceNode($nod2);
				} else {
					$nod->addChild($nod2);
				}
				
				delete($app_params{ $name });
			}
		}
	}

	# create response and attach request to it
	my ($resp, $root) = core::create_response($reqid, $MODULE);
	core::xml::copyNode($root, $app_req);

	# process by kernel
	$resp = core::kernel::process($reqid, $req, $app_req, %app_params);

	# fini
	return ($resp, core::CT_OK);
}

1;
