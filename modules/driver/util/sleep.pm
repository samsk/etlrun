# driver::util::sleep.pm
# - sleep driver
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::util::sleep;

use strict;
use warnings;

use Time::HiRes qw( );

use core;
use core::log;
use core::conf;
use core::time;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'util::sleep';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/util#sleep';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# get string timeout specification
	## @timeout
	my $timeout = core::xml::attrib($req, 'timeout', $NAMESPACE_URL);

	# get identificator
	## @id
	my $id = core::xml::attrib($req, 'id', $NAMESPACE_URL) || '';

	# try seconds attribute value if no timeout attribute
	my $secs = 0;
	if (!defined($timeout))
	{
		## @etlp_sleep:seconds
		$secs = core::xml::attrib($req, 'seconds', $NAMESPACE_URL)
			|| core::conf::get('driver.util.sleep.default', 1);
	}
	else
	{
		if (($secs = core::time::parse_offset($timeout)) < 0) {
			$secs = 3;
			core::log::PKG_MSG(LOG_FATAL, " - failed to parse timeout spec '%s', using %d sec default",
				$timeout, $secs);
		}
	}

	# sleep now if needed
	if ($secs)
	{
		my $max = core::conf::get('driver.util.sleep.max', -1);
		$secs = ($max < $secs) ? $max : $secs
			if ($max != -1);

		core::log::PKG_MSG(LOG_NOTICE, " - sleeping %0.2f seconds %s", $reqid, $secs, $id ? "[$id]" : '');
		Time::HiRes::sleep($secs);
		core::log::PKG_MSG(LOG_NOTICE, " - waking up", $reqid);
	}
	return (core::RESPONSE_NULL, core::CT_NULL);
}

1;
