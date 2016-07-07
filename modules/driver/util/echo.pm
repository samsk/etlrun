# driver::util::echo.pm
# - echo driver
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::util::echo;

use strict;
use warnings;

use Time::HiRes qw( );

use core;
use core::log;
use core::conf;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'util::echo';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/util#echo';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my $msg = $req->firstChild()->nodeValue()
		if ($req->firstChild());
	chomp($msg);

	print STDERR $msg . "\n";
	return (core::RESPONSE_NULL, core::CT_NULL);
}

1;
