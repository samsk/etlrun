# transform::null.pm
#
#	NULL transformation
#
# Copyright: Samuel Behan (c) 2011-2016
#
package transform::null;

use strict;
use warnings;

# internal
use core::log;


sub apply($$$$$%)
{
	my ($reqid, $req_doc, $doc, $xslt, $params, %params) = @_;
	core::log::SYS_CALL("%s, 0x%p, <DATA>, %s, <PARAMS>", $reqid, $req_doc, $xslt);

	# pass DOC back
	return $doc;
}

sub init($)
{
	return 1;
}

1;
