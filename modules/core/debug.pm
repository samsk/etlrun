# core::debug.pm
#
# Debugging functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::debug;

use strict;
use warnings;

# vars

# waitdebugger
sub waitdebugger()
{
	# gdb
	warn "attach debugger to pid: $$ and press space...";
	<STDIN>;
	return;
}

1;
