# driver::lock.pm
#	- locking/serialisation driver to prevent parallel runs
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::lock;

use strict;
use warnings;

use Fcntl qw(:flock);
use XML::LibXML;
use Time::HiRes qw( );

use core;
use core::log;
use core::conf;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'lock';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/lock';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# get attribs
	## @id   - lock unique name
	my $name = core::xml::attrib($req, 'id', $NAMESPACE_URL);
	die(__PACKAGE__ . ": id attribute not defined")
		if (!$name);

	## @soft - soft lock
	my $soft = core::xml::attrib($req, 'soft', $NAMESPACE_URL);
	## @retry  - 0 do not wait, < 0 wait forever
	my $retry = core::xml::attrib($req, 'retry', $NAMESPACE_URL);
	$retry = (defined($retry) ? $retry : core::conf::get('driver.lock.retry', -1));
	## @retry-sleep
	my $retry_sleep = core::xml::attrib($req, ['retry-sleep', 'retry_sleep'], $NAMESPACE_URL);
	$retry_sleep = defined($retry_sleep) ? $retry_sleep : core::conf::get('driver.lock.retry-sleep', 1);
	## @expire
	my $expire = core::xml::attrib($req, 'expire', $NAMESPACE_URL);
	$expire = defined($expire) ? $expire : core::conf::get('driver.lock.expire', 900);
	## @verbose
	my $verbose = core::xml::attrib($req, 'verbose', $NAMESPACE_URL);
	$verbose = ($verbose ? 1 : 0) || core::conf::get('driver.lock.verbose', 0);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);

	# lock file
	my $id = $name;
	$id =~ s:/:_:og;
	my $lock_file = core::conf::get('driver.lock.path', '/tmp') . '/.etllock_' . $id . '.lck';

	# opc/create lock file
	my $f;
RESTART:
	if (!open($f, '>>', $lock_file))
	{
		$root->addChild(core::raise_error($reqid, $MODULE, 500,
			_fatal => $resp,
			name => $name,
			id => $id,
			req => $req,
			msg => 'ERROR: failed to open lock file',
			lock => $lock_file,
			errno => $!));
		return ($resp, core::CT_ERROR);
	}

	# repeat
	my $tim_start = time();
	my $r_count = 0;
	my $nl_flag = 0;
	while ($retry < 0 || ($r_count < $retry || $r_count == 0))
	{
		$r_count++;

		# read current lock pid
		seek($f, 0, 1);
		my $lock_pid = <$f>;
		seek($f, 0, 1);

		# remove dead data
		$lock_pid =~ s/ .*$//og
			if ($lock_pid);

		# try to aquire lock
		if (flock($f, LOCK_EX | LOCK_NB))
		{	$nl_flag = 1; last;	}

		# check file
		my $tim = time();
		my @stat = stat($lock_file);
		if (!@stat)
		{	$nl_flag = 1; last;	}
		elsif ($expire && ($stat[9] + $expire) <= $tim && !$soft)
		{
			core::log::PKG_MSG(LOG_IMPORTANT - $verbose, " - lock '%s' expired, aquiring it forcibly [owner: %d]",
					$name, $lock_pid);
			rename($lock_file, $lock_file . '_' . $$);
			close($f);
			goto RESTART;
		}

		# sleep now
		if ($retry < 0 || $r_count < $retry)
		{
			core::log::PKG_MSG(LOG_WARNING - $verbose, " - lock '%s' sleep %0.2f secs [total %0.2f secs, retry %d/%d, owner: %d]",
					$name,
					$retry_sleep, $tim - $tim_start, $r_count, $retry,
					$lock_pid || -1);
			Time::HiRes::sleep($retry_sleep + (rand() * 0.01))
		}
	}

	# process
	if ($retry < 0 || $r_count < $retry || $nl_flag)
	{
		core::log::PKG_MSG(LOG_IMPORTANT - $verbose, " - lock '%s' aquired [total: %d secs]",
					$name, time() - $tim_start);

		# we could aquire lock to dead file, check this
		if (! -e $f)
		{
			close($f);
			goto RESTART;
		}

		# write our pid to lock file
		seek($f, 0, 1);
		syswrite($f, $$ . ' ');

		$resp = core::kernel::process($reqid, $doc, $req->firstChild(), %params);

		# release lock
		flock($f, LOCK_UN) || rename($lock_file, $lock_file . '__' . $$);
		close($f);

		core::log::PKG_MSG(LOG_IMPORTANT - $verbose, " - lock '%s' released",
					$name);
	}
	elsif (!$soft)
	{
		$root->addChild(core::raise_error($reqid, $MODULE, 504,
			_fatal => $resp,
			req => $req,
			name => $name,
			id => $id,
			msg => 'TIMEDOUT: lock timedout',
			retries => $r_count,
			expire => $expire,
			runtime => time() - $tim_start));
		close($f);
		return ($resp, core::CT_ERROR);
	}
	else
	{
		core::log::PKG_MSG(LOG_WARNING - $verbose, " - soft lock '%s' not aquired [total: %d secs]",
				$name, time() - $tim_start);

		$root->addChild(core::raise_error($reqid, $MODULE, 200,
			_fatal => $resp,
			name => $name,
			id => $id,
			req => $req,
			msg => 'OK: soft lock not aquired, skipping',
			retries => $r_count,
			runtime => time() - $tim_start,));
		close($f);
		return ($resp, core::CT_ERROR);
	}
	return (defined($resp) ? ($resp, core::CT_OK) : (core::RESPONSE_NULL, core::CT_NULL));
}

1;
