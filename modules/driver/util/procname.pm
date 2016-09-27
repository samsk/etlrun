# driver::util::procname.pm
# - process name change driver
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::util::procname;

use strict;
use warnings;

use core;
use core::log;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'util::echo';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/util#procname';

# orignal process name
my $ORIG_PROCNAME;

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	## @overwrite
	my $overwrite = core::xml::attrib($req, 'overwrite', $NAMESPACE_URL);

	## @format
	my $format = core::xml::attrib($req, 'format', $NAMESPACE_URL) || "%s - %s";

	my $msg = $req->firstChild()->nodeValue()
		if ($req->firstChild());

	# save initial procname
	$ORIG_PROCNAME = $0
		if (!defined($ORIG_PROCNAME));

	# change process name
	if (!$overwrite)
	{	$0 = sprintf($format, $ORIG_PROCNAME, $msg);	}
	else
	{	$0 = $msg;	}

	return (core::RESPONSE_NULL, core::CT_NULL);
}

1;
