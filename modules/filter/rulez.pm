# filter::rulez.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package filter::rulez;

use strict;
use warnings;

use Data::Dumper;

# internal
use core::log;
use core::conf;

my %FILTER_RULEZ;
my %FILTER_RULEZ_load;
END { %FILTER_RULEZ = (); %FILTER_RULEZ_load = (); }

sub _load_filter_rulez($$)
{
	my ($file, $opts) = @_;

	my $f = core::conf::file($file)
		|| return core::log::error(__PACKAGE__, "could not find file '$file'", undef);
	my (@rulez, $l);

	$FILTER_RULEZ_load{$file} = time();

	my $fd;
	open($fd, $f) || return core::log::error(__PACKAGE__, "can not open file '$file' - $!", undef);
	binmode($fd, ':utf8');
	while (($l = <$fd>))
	{
		chomp($l);
		next if ($l =~ /^\#/o || $l =~ /^\s*$/o);

		# recognize dynamic patters (those with subpattern variables)
		my $dyn = 1;
		my (@m) = split(/(?!\\)\s*==>\s*/o, $l, 2);
		@m = split(/(?!\\)\s*=>\s*/o, $l, 2), $dyn = 0
			if ($#m != 1);

		my ($match, $replace) = ($m[0], $m[1]);
		if ($dyn) {
			# dynamic patterns are potentionally unsafe
			die("SAFECHECK: dynamic match rulez are disabled  !\n")
				if (!core::conf::get("filter.rulez.dynamic", 1));

			if ($replace =~ /^".*"$/o || $replace =~ /^'.*'$/o) {
					$replace = $replace;
			} else {
				$replace =~ s/\"/\\"/og;
				$replace = '"' . $replace . '"';
			}
		}

		local $@;
		my $sigWARN = $SIG{__WARN__};

		# precompile regex and verify replace eval is correct
		my $rule;
		eval {
			my $ok = 1;
			my $test = 'x';
			my $regex_match = qr!$match!i;

			$SIG{__WARN__} = sub { $@ = "@_"; $ok = 0; };
			die("regex string invalid\n")
				if (!$regex_match);
			# XXX: check eval for $1 ... $9 submatches
			die("dynamic replace eval string invalid\n")
				if ($dyn && ($test !~ s/(((((((((x)))))))))|$regex_match/$replace/ugsee
						|| !$ok));

			$rule = {
				match => $regex_match,
				replace => $replace,
				dynamic => $dyn
			};
		};
		$SIG{__WARN__} = $sigWARN;
		die(__PACKAGE__ . " - failed to compile regexp '$match' => '$replace'\nERROR: $@\n")
			if ($@);

		push(@rulez, $rule)
			if ($rule);
	}
	close($fd);
	$FILTER_RULEZ{$file} = \@rulez;
	return 1;
}

sub apply($$$$)
{
	my ($reqid, $type, $data, $opts) = @_;
	core::log::SYS_CALL("%s, %s, <DATA>", $reqid, $type);

	# file
	my $file = 'rulez.filter';
	foreach my $v_par (split(/\s+/, $opts))
	{	$file = $1 if($v_par =~ /^file=(.+)\s*$/o);	}

	# load filter map
	return undef
		if ((!$FILTER_RULEZ_load{$file} || $FILTER_RULEZ_load{$file} < core::conf::FLAG_RELOAD_TIME())
			&& !_load_filter_rulez($file, $opts));

	my $changed = 0;
	map {
		my $change;
		my ($mat, $rep) = ($_->{match}, $_->{replace});

		if ($_->{dynamic}) {
			no warnings;
			$change = ($$data =~ s/$mat/$rep/ugsee);
		} else {
			$change = ($$data =~ s/$mat/$rep/ugs);
		}

		$changed += $change;
		} @{ $FILTER_RULEZ{$file} };
	return $changed;
}

1;
