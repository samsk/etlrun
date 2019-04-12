# driver::embed.pm
#  -- simple transformation driver
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::transform;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::kernel;
use core::transform;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'transform';
our $MODULE_RESULT = 'transform-result';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/transform';
our $NAMESPACE_RESULT_URL = $NAMESPACE_URL . '/result';

# globals
my $MODULE_GLOBAL_export = '-' . __PACKAGE__ . '_export';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# response
	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# get attributes
	## @stylesheet
	my $tpl = core::xml::attrib($req, 'stylesheet', $NAMESPACE_URL);
	die(__PACKAGE__ . ": no stylesheet attribute given")
		if (!$tpl);

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
	my $req_node = core::get_data_request($req, $NAMESPACE_URL, $req->localName());
	die(__PACKAGE__ . ": request node not found")
		if (!$req_node);

	# export params for subrequest
	$params{ $MODULE_GLOBAL_export } = \%export_params
		if (%export_params);

	# exec req
	my $resp2 = core::kernel::process($reqid, $doc, $req_node, %params) || $req_node;

	# apply stylesheet
	my $req_doc = core::xml::isDocument($resp2);
	my $resp3 = core::transform::apply($reqid, $doc, $resp2, $tpl, %local_params, %params);

	# add to response
	if (!defined($resp3))
	{
		$nod->addChild(core::raise_error($reqid, $MODULE, 404,
			req => $resp2,
			transform => $tpl,
			msg => 'BAD REQUEST: transformation failed'));
	}
	else
	{
		my $uri = core::get_uri($resp2);

		$resp2 = undef;
		my $resp4 = core::xml::isDocument($resp3) ? $resp3->documentElement() : undef;
		if (defined($resp4))
		{	core::xml::moveNode($nod, $resp4);	}
		else
		{
			core::log::SUB_MSG(LOG_WARNING, " - got textual result, maybe because INPUT xml was not a DOCUMENT but a NODE")
				if (!$req_doc);

			# possibly invalid transformation resulting in plain text document
			my $text = $resp->createElementNS($NAMESPACE_RESULT_URL, $MODULE_RESULT . ':text');
			$text->appendText(core::xml::nodeValue($resp3));
			$nod->addChild($text);
		}

		# URI must be there
		core::set_uri($resp, $uri)
			if (defined($uri));
	}
	return ($resp, core::CT_OK);
}

1;
