# transform::xpath.pm
#
#	XPATH select transformation
#
# Note: use _DEF_ in xpath as namespace for searching in default namespace
#
# Copyright: Samuel Behan (c) 2012-2016
#
package transform::xpath;

use strict;
use warnings;

use Data::Dumper;

# internal
use core;
use core::log;

sub apply($$$$$%)
{
	my ($reqid, $req_doc, $doc, $xslt, $params, %params) = @_;
	core::log::SYS_CALL("%s, 0x%p, <DATA>, %s, <PARAMS>", $reqid, $req_doc, $xslt);

	# get data root
	my ($data) = core::get_data_root($doc);
	($data) = core::get_data($doc)
		if (!$data);

	# namespaces from document
	my %namespace;
	my (@nsobjects) = $data->getNamespaces();
	foreach my $ns (@nsobjects)
	{
		$namespace{ $ns->declaredPrefix() || core::NS_DEFAULT } = $ns->declaredURI();
	}
	# user defined namespace
	if ($xslt =~ s/\?(.*)$//o)
	{
		my $paramstr = $1;
		my @params = split(/&/o, $paramstr);

		foreach my $param (@params)
		{
			my ($ns, $uri) = split(/=/o, $param, 2);
			$namespace{ $ns } = $uri;
		}
	}

	# select
	my (@nodes) = core::findnodes($doc, $xslt, %namespace);

	my ($resp, $root) = core::xml::create_document('xpath');
	core::xml::copyNode($root, @nodes);

	# pass DOC back
	return $resp;
}

sub init($)
{
	return 1;
}

1;
