# core::context.pm
#
# Context functions
# Holds runtime specific data (like core::conf config)
#
# Copyright: Samuel Behan (c) 2015-2016
#
package core::context;

use strict;
use warnings;

use core::util;

use Storable qw(freeze thaw);

my @STACK = (
	&_init_new(),
);

sub _init_new() {
	return {};
}

sub _export_ctx(;$) {
	my ($full) = @_;

	my %ctx = %{$STACK[$#STACK]};
	# inherit stack, either - current and previous, or all
	for(my ($ii, $cnt) = ($#STACK - 1, 0);
		($ii >= 0) && ($full || $cnt < 1);
			$ii--, $cnt++) {

		my @keys = sort(core::util::uniq(keys(%ctx),
					keys(%{$STACK[$ii]})));
		foreach my $key (@keys) {
			next
				if (!exists($ctx{$key}) || !exists($STACK[$ii]->{$key}));

			# it is expected and forced that module subcontext is hash
			my $fn = $key . '::_merge_context';
			if (eval "defined(&$fn)") {
				# <package>::_merge_context(\%old, \%new)
				$ctx{$key} = &$fn($ctx{$key}, $STACK[$ii]->{$key});
			} else {
				%{$ctx{$key}} = ($ctx{$key}, $STACK[$ii]->{$key});
			}
		}
	}
	return \%ctx;
}

# create([ $import_data, $replace_context ])
sub create(;$$) {
	my ($data, $replace) = @_;

	my $ctx = _init_new();

	# without merge
	%$ctx = (%$ctx, _export_ctx())
		if (!$replace);
	if ($data) {
		my $import = thaw($data);
		# this is override not merge
		%$ctx = (%$ctx, %$import);
	}
	push(@STACK, $ctx);
	return $ctx;
}

# current(): $package_context
sub current() {
	my ($package) = caller();

	my $ptr = \$STACK[$#STACK]->{$package};
	if (!defined($$ptr)) {
		$$ptr = {};
	}
	return $$ptr;
}

# release()
sub release() {
	pop(@STACK);
	return 1;
}

# export(): $export_data
sub export() {
	return freeze(_export_ctx());
}

1;
