# convert::application::xml.pm
#
# Copyright: Samuel Behan (c) 2011-2018
#
package convert::application::xml;

use strict;
use warnings;

use convert::text::xml;

sub from(@)
{
	return &convert::text::xml::from(@_);
}
1;
