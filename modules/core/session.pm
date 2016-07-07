# core::session.pm
#
# SESSION manipulation functions
#
# Copyright: Samuel Behan (c) 2014-2016
#
package core::session;

use strict;
use warnings;

#use Data::Dumper;

use core::log;
use core::lru;
use core::conf;

my (%CACHE, %CACHE_load);
END { undef %CACHE; undef %CACHE_load };

# cache($name, $key [, $data])
sub cache($$;$)
{
	my ($name, $key, $data) = @_;

	core::log::SYS_CALL("'%s', '%s', %s", $name, $key, $data ? '<DATA>' : '');

	# check for reload event
	if (!exists($CACHE_load{$name})
		|| $CACHE_load{$name} < core::conf::FLAG_RELOAD_TIME())
	{
		core::lru::flush($CACHE_load{$name});
		$CACHE_load{$name} = time();
	}

	return core::lru::get($CACHE{$name}, $key)
		if (!defined($data));

	return core::lru::set($CACHE{$name}, $key, $data,
		core::conf::get('core.session.cache-size', 30));
}

1;

