# driver::exec.pm
#  -- advanced exec driver
#
# Copyright: Samuel Behan (c) 2014-2016
#
package driver::exec;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'exec';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/exec';

# globals
my $MODULE_GLOBAL_export = '-' . __PACKAGE__ . '_export';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# response
	#my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# get exported params
	my (%local_params, %export_params);
	%local_params = %params;
	%local_params = %export_params = %{ $params{ $MODULE_GLOBAL_export } }
		if (exists($params{ $MODULE_GLOBAL_export }));

	# get params
	## param
	my (@param_nodes) = core::findnodes($req, $MODULE . ':param', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@param_nodes)
	{
		## @name
		my $name = core::xml::attrib($nod, 'name', $NAMESPACE_URL);
		die(__PACKAGE__ . ": name attribute missing")
			if (!$name);
		## @export
		my $export = core::xml::attrib($nod, 'export', $NAMESPACE_URL);

		$local_params{ $name } = core::xml::nodeValue($nod);
		$export_params{ $name } = $local_params{ $name }
			if ($export);
	}

	# get req node
	my $req_node = core::get_data_request($req, $NAMESPACE_URL);
	die(__PACKAGE__ . ": request node not found")
		if (!$req_node);

	# export params for subrequest
	$params{ $MODULE_GLOBAL_export } = \%export_params
		if (%export_params);

	# exec req
	my $resp = core::kernel::process($reqid, $doc, $req_node, (%local_params, %params));

	# request must execute
	die(__PACKAGE__ . ": failed to execute given request")
		if (!$resp);

	return ($resp, core::CT_OK);
}

1;
