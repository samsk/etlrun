# driver::url.pm
# - null driver
#
# Copyright: Samuel Behan (c) 2012-2016
#
package driver::null;

use strict;
use warnings;

use core;
use core::log;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'null';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/null';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);
	core::xml::copyNode($root, $req->firstChild());

	return ($resp, core::CT_OK);
}

# postprocess
sub postprocess($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	return ($req, core::CT_OK);
}

1;
