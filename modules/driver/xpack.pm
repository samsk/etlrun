# driver::xpack.pm
#
#
# Copyright: Samuel Behan (c) 2014-2016
#
package driver::xpack;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::xml;

## NAMESPACE: $MODULE
our $MODULE = 'xpack';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/xpack';

# fetch
sub postprocess($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);


}

1;
