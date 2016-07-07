# core::util.pm
#
# various helper functions
#
# Copyright: Samuel Behan (c) 2015-2016
#
package core::util;

use strict;
use warnings;

sub uniq(@) {
	my %seen;
	return grep(!$seen{$_}++, @_);
}

1;
