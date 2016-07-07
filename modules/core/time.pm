# core::time.pm
#
# Time functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::time;

use strict;
use warnings;

#use Data::Dumper;

my %MULTI_MAP = (
	qr/^s(ec(onds?)?)?$/i		=> 1,
	qr/^m(in|ins|inutes?)?$/i	=> 60,
	qr/^h(ours?)?$/i		=> 60 * 60,
	qr/^d(ays?)?$/i			=> 60 * 60 * 24,
	qr/^w(eeks?)?$/i		=> 60 * 60 * 24 * 7,
);

# parse_offset($string): seconds
sub parse_offset($)
{
	my ($str) = @_;

	# check parametrizing function
	my $funct = $1
		if ($str =~ s/^\s*(\w+?):\s*//o);

	# parse
	my ($offset, $str_old)  = (0);
	while (length($str) && (!defined($str_old) || $str_old ne $str))
	{
		$str_old = $str;
		return wantarray ? (-1, "failed to parser '$str'") : -1
			if ($str !~ s/^\s*(\d+((\.|,)\d+)?)(\s*(\w+)?)?(\s+\+)?//o);
		my ($count, $multi) = ($1, $5);

		foreach $_ (keys(%MULTI_MAP))
		{
			next if (!defined($multi) || $multi !~ /$_/);
			$count *= $MULTI_MAP{$_};
			$multi = undef;
			last;
		}
		return wantarray ? (-1, "unknown multiplier '$multi'") : -1
			if (defined($multi));
		$offset += $count;
	}

	# no functions
	return $offset if (!defined($funct));

	# use parametrizations
	if ($funct eq 'random')
	{
		$offset = (rand($offset * 2) % $offset) + rand(0.99);
	}
	elsif ($funct =~ /^random_hi(\d+)$/o)
	{
		my $offset_hi = $offset * ( (100 - ($1 % 100)) / 100);
		$offset = $offset_hi + rand(($offset - $offset_hi));
	}

	# return
	return $offset;
}

# now() : unixtime
sub now()
{
	return core::conf::get('core.time', time()) + core::conf::get('core.time-offset', 0);
}

1;
