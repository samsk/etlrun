# core::cache.pm
#
# Caching module
#
# Copyright: Samuel Behan (c) 2015-2016
#
package core::cache;

use strict;
use warnings;

#use Data::Dumper;

# internal modules
use core::lru;
use core::log;
use core::conf;
use core::auto;

my ($STORE_FX, $INVALIDATE_FX, $FETCH_FX, $ATTRIB_FX);

# _init()
sub _init
{
	my $module = 'cache::' . core::conf::get('cache.driver', 'fs');

	die(__PACKAGE__ . ": failed to load module '$module'")
		if (!core::auto::load($module));

	no strict 'refs';
	my $init = $module . '::init';
	die(__PACKAGE__ . ": failed to init module '$module'")
		if (!&$init());

	# init handlers
	$STORE_FX = $module . '::store';
	$INVALIDATE_FX = $module . '::invalidate';
	$FETCH_FX = $module . '::fetch';
	$ATTRIB_FX = $module . '::attrib';
	return 1;
}

# store($key, $data, $expire, $timestamp [, $version ])
sub store($$$;$)
{
	my ($key, $data,  $expire, $timestamp, $version) = ($_[0], $_[1], $_[2], $_[3], $_[4] || 0);

	no strict 'refs';
	return &$STORE_FX($key, $data, $expire, $timestamp, $version)
		if (defined($STORE_FX));

	# log
	core::log::SYS_CALL("%s, <DATA>, %d, %d, %s", $key, $expire, $timestamp, $version);
	_init();
	return &$STORE_FX($key, $data, $expire, $timestamp, $version);
}

# invalidate($key)
sub invalidate($)
{
	my ($key) = @_;

	no strict 'refs';
	return &$INVALIDATE_FX($key)
		if (defined($INVALIDATE_FX));

	# log
	core::log::SYS_CALL("%s", $key);
	_init();
	return &$INVALIDATE_FX($key)
}

# attrib($key): %attribs
sub attrib($)
{
	my ($key) = @_;

	no strict 'refs';
	return &$ATTRIB_FX($key)
		if (defined($ATTRIB_FX));

	# log
	core::log::SYS_CALL("%s", $key);
	_init();
	return &$ATTRIB_FX($key)
}

# valid_until($key): timestamp
sub valid_until($)
{
	my ($key) = @_;

	my $dat = attrib($key);
	return $dat->{'expire'};
}

# is_valid($key [, $timestamp = now() ]): bool
sub is_valid($;$)
{
	my $key = shift;
	my $ts = shift || time();

	my $cache_ts = valid_until($key);

	# check data
	return ($cache_ts != 0 && $cache_ts <= $ts);
}

# created($key): timestamp
sub created($)
{
	my ($key) = @_;

	my $dat = attrib($key);
	return $dat->{'timestamp'} || $dat->{'expire'};
}

# fetch($key [, $timestamp, $version ]) : $data
sub fetch($;$$)
{
	my ($key, $timestamp, $version) = ($_[0], $_[1], $_[2] || 0);

	no strict 'refs';
	return &$FETCH_FX($key, $timestamp, $version)
		if (defined($FETCH_FX));

	# log
	core::log::SYS_CALL("%s, %d, %s", $key, $timestamp, $version);
	_init();
	return &$FETCH_FX($key, $timestamp, $version);
}

1;
