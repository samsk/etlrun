# core::crypt.pm
#
# Crypto related functions
#
# Copyright: Samuel Behan (c) 2016
#
package core::crypt;

use strict;
use warnings;

my $SEED;
my $SEED_MIX = hex(substr(sprintf('%p', $SEED), -6, 6));

sub _init_rand()
{
	# silly seed
	my $seed = time() * $$
		+ (hex(substr(sprintf('%p', $SEED_MIX), -5, 5)) - $$ * 13)
		- ($$ % ($( + 1)) * $^T;

	# silly reseed
	my $iter = 1;
	srand($seed);
	do {
		my $seed1 = $seed;
		$seed = rand();

		if ($$ % 3) {
			srand($seed * $iter);
		} elsif (($seed - $iter) % 2) {
			srand($seed1 % $iter);
		} else {
			srand($seed * $seed1 * $iter);
		}
		$seed = rand() + $iter;

		$SEED_MIX = $seed
			if (($iter % 3) == 0);
	} while((($seed * 10000000) % 13) != 0
		&& $iter++ < (($$ % 23) + 3));
	$SEED = rand();
	return;
}
_init_rand();

sub rand()
{
	return rand();
}

1;
