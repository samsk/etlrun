# driver::group::parallel.pm
# - request grouping with parallelization
#	uses fork-per-request strategy, exchanging costs of fork()ing of
#	new process for implementation easiness and robustness.
#	NOTE: this is the dumb, quick and flawless solution.
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::group::parallel;

use strict;
use warnings;

use Data::Dumper;
use XML::LibXML;
use POSIX ":sys_wait_h";
use IO::Handle;
use IO::Select;
use Time::HiRes qw(usleep);
use Errno qw(EAGAIN);

$SIG{PIPE} = 'IGNORE';
$SIG{CHLD} = 'IGNORE';

use core;
use core::log;
use core::xml;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'group::parallel';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/group/parallel';

# _collect($notify_pipe, \@pids, $wait): $active_pids_count
sub _collect($\@;$)
{
	my ($notif, $pids, $wait) = @_;
	core::log::SYS_CALL("<NOTIF>, <PIDS>, %d", $wait);

	# build file vec
	my $act = 0;
	my $fdset = IO::Select->new($notif);
	foreach my $p (@$pids)
	{
		next if (!$p->{active});
		$fdset->add($p->{fh});
		$act++;
	}

	# nothing active anymore
	return 0 if (!$act);

	# do select
	do {
RETRY:
		my (@fdread) = $fdset->can_read(($wait) ? undef : 0.002);

		# no info
		return $act if (!@fdread);

		# notifier informed
		if (grep($notif, @fdread))
		{
			my ($dat, $len);
			$len = sysread($notif, $dat, 301);

			# handle EAGAIN
			usleep(666), goto RETRY
				if ($!{EAGAIN});

			# other fatal error
			die(__PACKAGE__ . ": fatal comunication problem with child (data: $dat, len: $len, err: $!)")
				if (!$len || ($len % 3) != 0);

			foreach my $id (unpack("(A3)*", $dat))
			{
				# id is with offset
				my $pid = $$pids[$id - 1];

				# got OK child response
				$pid->{active} = 0;

				# test check byte
				my $check = '';
				if (sysread($pid->{fh}, $check, 1) == 1)
				{
					my $err;

					core::log::PKG_MSG(LOG_NOTICE, ": got response from child #%d", $id);
					if ($check eq 'X')
					{
						($pid->{resp}, $err) = core::xml::parse($pid->{fh});
						die(__PACKAGE__ . ": failed to parse response - $err")
							if ($err);
					}
					elsif ($check eq 'Q')
					{
						# empty response, just skip
						$pid->{resp}	= core::RESPONSE_NULL;
					}
				}
				else {
					core::log::PKG_MSG(LOG_IMPORTANT, ": incorrect response from child #%d", $id);
				}
				$fdset->remove($pid->{fh});
				close($pid->{fh});

				# wait a while and reap all our zombies
				select(undef, undef, undef, 0.05);
				foreach (@$pids)
				{
					next
						if ($_->{active});
					waitpid($_->{pid}, WNOHANG);
				}

				# decreate active count
				$act--;
			}
		}

		# this is incorrect response (notifier should be always informed as first)
		foreach my $fd (grep { $_ != $notif } @fdread)
		{
			my ($pid) = grep { $_->{fh} eq $fd } @$pids;

			die(__PACKAGE__ . ": response from unknown children, universe broken !")
				if (!$pid);

			# must not be active anymore
			next if (!$pid->{active});
			core::log::PKG_MSG(LOG_IMPORTANT, ": unexpected response from child #%d", $pid->{id});

			# close the child
			$pid->{active} = 0;
			$fdset->remove($pid->{fh});
			close($pid->{fh});

			# reap zombie
			select(undef, undef, undef, 0.03);
			waitpid($pid->{pid}, WNOHANG);

			# decreate active count
			$act--;
		}
	} while($wait && $act > 0);

	# return active count
	core::log::PKG_MSG(LOG_DETAIL, ": active childs = %d (wait = %d)", $act, $wait);
	return $act;
}

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);

	## @parallel
	my $parallel = core::xml::attrib($req, 'parallel', $NAMESPACE_URL) || core::conf::get('driver.group.parallel', 10);
	my @childs = $req->nonBlankChildNodes();

	# process
	my @pids;
	my ($p_act, $r_sent) = (0, 0);

	my ($p_rd, $p_wr);
	pipe($p_rd, $p_wr);
	$p_rd->autoflush(1);
	$p_rd->blocking(0);
	$p_wr->autoflush(1);
	foreach my $nod (@childs)
	{
		# skip non-elements
		next if ($nod->nodeType != XML_ELEMENT_NODE);

		# create pipe
		my ($c_rd, $c_wr);
		pipe($c_rd, $c_wr);

		# process
		$r_sent++;
		$p_act++;
		my $pid = fork();

		die(__PACKAGE__ . ": booting executor failed - $!")
			if (!$pid < 0);
		my $id = $r_sent;

		### CHILD ###
		if (!$pid)
		{
			# set executor name
			my $name = core::xml::attrib($nod, 'name', $NAMESPACE_URL) || '#' . $id;
			$0 = sprintf('%s %s', 'ETL', $name);

			core::log::PKG_MSG(LOG_NOTICE, ": processing request #%d (%s)", $id, $name);

			# close pipes
			close($p_rd);
			foreach (@pids)
			{	close($_->{fh});	}
			close($c_rd);
			$c_wr->autoflush(1);

			# execute by kernel
			my $dat = core::kernel::process($reqid . '_' . $name, $doc, $nod, %params);

			core::log::PKG_MSG(LOG_NOTICE, ": request #%d (%s) completed", $id, $name);

			# inform about completion (can handle 'only' 999 childs!)
			syswrite($p_wr, sprintf("%03d", $id)) ||
					die(__PACKAGE__ . ": failed to send notification from #$id [$!]");

			# write check byte
			if ($dat)
			{
				syswrite($c_wr, 'X') || die(__PACKAGE__ . ": failed to write X check byte [$!]");
				# write result
				$dat->toFH($c_wr, 0)
			}
			else
			{
				syswrite($c_wr, 'Q') || die(__PACKAGE__ . ": failed to write Q check byte [$!]");
			}
			close($c_wr);
			exit(0);
		}
		### PARENT ###
		else
		{
			# close write pipe
			close($c_wr);
			$c_rd->autoflush(1);

			# add to wait list
			push(@pids, { id => $id, fh => $c_rd, pid => $pid,
					req => $nod, active => 1 });
		}

		# collect responses (or wait for them if needed)
		$p_act = _collect($p_rd, @pids, ($p_act >= $parallel));
	}

	# collect remaining responses
	$p_act = _collect($p_rd, @pids, 1);
	close($p_rd);

	die(__PACKAGE__ . ": failed to collect all responses, $p_act executors still active !")
		if ($p_act);

	foreach my $pid (@pids)
	{
		if (exists($pid->{resp}))
		{
			if (defined($pid->{resp})
				&& $pid->{resp} != core::RESPONSE_NULL
				&& $pid->{resp}->documentElement()->firstChild()) {

				foreach my $child ($pid->{resp}->documentElement()->childNodes()) {
					core::xml::moveNode($root, $child);
				}
			}
		}
		else
		{
			$root->addChild(core::raise_error($reqid, $MODULE, 500,
				_fatal => $resp,
				req => $pid->{req},
				msg => 'INTERNAL ERROR: no response from executor',
				id => $pid->{id}));
		}
	}
	return ($resp, core::CT_OK);
}

1;
