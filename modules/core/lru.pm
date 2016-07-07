# core::lru.pm
#
# LRU functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::lru;

use strict;
use warnings;

use Data::Dumper;

# get($ctx, $key)
sub get($$)
{
	my ($ctx, $key) = @_;

	return undef
		if (!defined($ctx) || !exists($ctx->{ -key }->{ $key }));

	$ctx->{ -key }->{ $key }->{ -lid } = ++$ctx->{ -lid }
		if ($ctx->{ -key }->{ $key }->{ -lid } != $ctx->{ -lid });
	return $ctx->{ -key }->{ $key }->{ -dat };
}

# last($ctx)	-- get last recently used key
sub last($)
{
	my ($ctx) = @_;

	# sort
	my @lru = sort { $ctx->{ -key }->{ $a }->{ -lid } <=> $ctx->{ -key }->{ $b }->{ -lid } }
				keys %{ $ctx->{ -key } };

	my $key = pop(@lru);

	return undef
		if (!defined($key));
	return wantarray ? ($key, $ctx->{ -key }->{ $key }->{ -dat }) : $key;
}

# set($ctx, $key, $data [, $size, $release_function ])
sub set(\$$$;$$)
{
	my ($ctx, $key, $dat, $size, $fx) = ($_[0], $_[1] || die(), $_[2], $_[3] || 5, $_[4]);

	$$ctx = { -key => {}, -lru => [], -lid => 0 }
		if (!defined($$ctx));

	$$ctx->{ -key }->{ $key }->{ -dat } = $dat;
	$$ctx->{ -key }->{ $key }->{ -fx  } = $fx;
	$$ctx->{ -key }->{ $key }->{ -lid } = ++$$ctx->{ -lid };	# last use id

	if (keys(%{ $$ctx->{-key} }) > $size)
	{
		my @lru = sort { $$ctx->{ -key }->{ $a }->{ -lid } <=> $$ctx->{ -key }->{ $b }->{ -lid } }
					keys %{ $$ctx->{ -key } };

		@lru = splice(@lru, 0, keys(%{ $$ctx->{-key} }) - $size);
		foreach $key (@lru)
		{
			$fx = $$ctx->{ -key }->{ $key }->{ -fx  };
			&$fx($$ctx->{ -key }->{ $key }->{ -dat })
				if (defined($fx));
			delete($$ctx->{ -key }->{ $key });
		}

		return ($dat, @lru)
			if (wantarray);
	}
	return $dat;
}

# del($ctx, $key, $release)
sub del($$;$)
{
	my ($ctx, $key, $release) = @_;

	return undef
		if (!defined($ctx) || !exists($ctx->{ -key }->{ $key }));

	my $dat = $ctx->{ -key }->{ $key }->{ -dat  };
	my $fx  = $ctx->{ -key }->{ $key }->{ -fx  };
	delete($ctx->{ -key }->{ $key });

	&$fx($dat)
		if (defined($fx) && $release);
	return $dat;
}

# flush($ctx)
sub flush(\$)
{
	my $ctx = shift;

	$$ctx = { -key => {}, -lru => [], -lid => 0 };
	return 1;
}

# __test
sub __test()
{
	my $DAT;

	warn "--STA--";

	set($DAT, 'k1', 1, 3, sub { print "k1: $_[0]\n" });
	set($DAT, 'k2', 2, 3, sub { print "k2: $_[0]\n" });
	set($DAT, 'k3', 3, 3, sub { print "k3: $_[0]\n" });
	warn 'LAST:' . core::lru::last($DAT);
	set($DAT, 'k4', 4, 3, sub { print "k4: $_[0]\n" });
	set($DAT, 'k5', 5, 3, sub { print "k5: $_[0]\n" });
	get($DAT, 'k5');
	warn 'LAST:' . core::lru::last($DAT);
	set($DAT, 'k6', 6, 3, sub { print "k6: $_[0]\n" });
	get($DAT, 'k4');
	warn 'LAST:' . core::lru::last($DAT);
	warn 'LAST:' . core::lru::last($DAT);
	del($DAT, 'k5');
	set($DAT, 'k7', 7, 2, sub { print "k7: $_[0]\n" });
	warn 'LAST:' . core::lru::last($DAT);

	warn Dumper($DAT);
	warn "--FIN--";

	# released 1,2,3,5,6
	# remains  4,7
}

1;
