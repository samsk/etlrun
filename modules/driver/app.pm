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
use core::conf;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'app';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/app';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

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

		return $app_req
			if (core::get_error($app_req));
		$app_req = $app_req->documentElement()->firstChild()
			if ($app_req && $app_req->documentElement());
	}
	else
	{
		## app:req
		($app_req) = core::findnodes($req, 'app:req[1]/*[1]', $MODULE => $NAMESPACE_URL);
	}

	# FIXME: not raising exception as we should !!!
	die(__PACKAGE__ . ": no or invalid request/url defined !")
		if (!defined($url) && !defined($app_req));

	## app:conf[1]		- app configuration
	my @conf_nodes = core::findnodes($req, 'app:conf', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@conf_nodes)
	{
		## app:conf/@name
		my $name = core::xml::attrib($nod, 'name', $NAMESPACE_URL);

		# FIXME: not raising exception as we should !!!
		die(__PACKAGE__ . ": config without name !")
			if (!$name);

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
		## app:arg/@default
		my $def = core::xml::attrib($nod, 'default', $NAMESPACE_URL);

		# FIXME: not raising exception as we should !!!
		die(__PACKAGE__ . ": argument without name !")
			if (!$name);
		die(__PACKAGE__ . ": duplicate argument '$name' !")
			if (exists($args{ $name }));

		# add
		$args{ $name } = { def => $def };
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
			my $is_append = 1
				if ($aname && $aname =~ s/\+$//o);

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
				if (!$is_append)
				{
					foreach my $child ($nod->childNodes())
					{
						$nod->removeChild($child);
					}
				}

				# add value
				my $val = exists($params{ $name }) ? $params{ $name } : $args{ $name }->{def};
				$nod->appendText(defined($val) ? $val : '');
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
