# convert::application::json.pm
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::application::json;

use strict;
use warnings;

use convert::text::json;

sub from(@)
{
	return &convert::text::json::from(@_);
}
1;
