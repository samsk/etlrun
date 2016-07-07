# convert::application::javascript.pm
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::application::javascript;

use strict;
use warnings;

use convert::text::javascript;

sub from(@)
{
	return &convert::text::javascript::from(@_);
}

1;

