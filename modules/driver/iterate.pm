# driver::iterate.pm
# - perform data iteration
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::iterate;

use strict;
use warnings;

use XML::LibXML;
use Scalar::Util qw(looks_like_number);

use core;
use core::log;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'iterate';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/iterate';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);

	# get attributes
	## @limit
	my $limit = core::xml::attrib($req, 'limit', $NAMESPACE_URL)
				|| core::conf::get('driver.iterate.limit', 100);
	die(__PACKAGE__ . ": no or invalid transaction attribute given")
		if (!$limit || !looks_like_number($limit));

#	## @offset
#	my $offset = core::xml::attrib($req, 'offset', $NAMESPACE_URL) || 0;
#	die(__PACKAGE__ . ": invalid offset attribute given")
#		if ($offset && $offset !~ /^\d+$/o);
	## @max
	my $max = core::xml::attrib($req, 'max', $NAMESPACE_URL) || 0;
	die(__PACKAGE__ . ": invalid max attribute given")
		if ($max && !looks_like_number($max));

	# get req node
	$req = $req->firstChild();
	while (defined($req) && $req->nodeType() != XML_ELEMENT_NODE
		&& (!$req->namespaceURI()
		|| $req->namespaceURI() ne $NAMESPACE_URL))
	{	$req = $req->nextSibling();	}
	die(__PACKAGE__ . ": request node not found")
		if (!$req);

	# find iterator data
	# /*/*[@iterator = 1]
	my $iterator = core::findnodes($req, "//*[\@$MODULE:iterator]", $MODULE => $NAMESPACE_URL);
	die(__PACKAGE__ . ": no iterator request found")
		if (!$iterator);

	# iterate
	my $pos = 0;
	my $iterator_id;
	while (!$max || $pos < $max)
	{
		my %local_params = %params;

		## DRIVER -limit
		$local_params{-limit}		= $limit;
		## DRIVER -iterator
		$local_params{-iterator}	= $iterator_id;

		my $iter_resp = core::kernel::process($reqid, $doc, $req, %local_params);
		return undef if (!$iter_resp);
		my ($iter_root) = core::get_data_root($iter_resp);

		# get iterator ident
		## DRIVER @etl:iterator
		$iterator_id = core::xml::attrib($iter_root, core::ATTR_ITERATOR, core::NAMESPACE_URL)
				|| core::xml::attrib($iter_root, core::ATTR_ITERATOR, core::NAMESPACE_URL);

		# copy nodes
		core::xml::copyNode($root, $iter_root);

		# no continue hint
		last if (!defined($iterator_id));

		# move offset
		$pos += $limit;
	}

	return ($resp, core::CT_OK);
}

1;
