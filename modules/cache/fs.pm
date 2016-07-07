# cache::fs.pm
#
# Caching module
#
# Copyright: Samuel Behan (c) 2011-2016
#
package cache::fs;

use strict;
use warnings;

#use Data::Dumper;
use Encode qw(encode_utf8);
use Digest::SHA1 qw(sha1_hex);
use Storable qw(store_fd fd_retrieve file_magic);

# internal modules
use core::fs;
use core::log;
use core::lru;
use core::conf;

my ($CACHE, $TS_CACHE);
END { $CACHE = {}; undef $CACHE; $TS_CACHE = {}; undef $TS_CACHE; }

# config
my $CACHE_DIR  = 'etlcache';
my $CACHE_ROOT = '/tmp/' . $CACHE_DIR;

# params
my $EXT_CACHE	= '.cache';
my $EXT_TS	= '.ts';
my $EXT_DIDX	= '.didx';

# _get_file_path($key) : ($key_path)
sub _get_file_path($)
{
	my ($key) = @_;

	# key sanity
	$key =~ s/\.\./_/og;

	# split key
	my $hash_parts = core::conf::get('cache.fs.hash-parts', 3);
	if ($hash_parts != 0)
	{
		# fixme: spliting creates also empty elements
		my @key_parts = split(/(?=\w)(\w)/, $key, $hash_parts + 1);
		$key = join('/', @key_parts);
	}

	return $key;
}

sub _ts_read($)
{
	my ($time_file) = @_;

	# use ts cache
	my $dat = core::lru::get($TS_CACHE, $time_file);

	return (wantarray ? @{$dat} : ${$dat}[0])
		if (defined($dat));

	# read file
	return undef
		if (!open(F, $time_file));

	# read data
	my $lin = <F>;
	close(F);

	# check data
	return undef
		if (!$lin);

	# parse data
	chomp($lin);
	my @arr = split(/\s/o, $lin);

	# cache data
	core::lru::set($TS_CACHE, $time_file, \@arr, core::conf::get('cache.fs.ts-lru-size', 100));
	return (wantarray ? @arr : $arr[0]);
}

# store($key, $data, $expire, $timestamp [, $version ])
sub store($$$;$)
{
	my ($key, $data,  $expire, $timestamp, $version) = @_;

	core::log::SYS_CALL(3, "%s, <DATA>, %d, %d, %s", $key, $expire, $timestamp, $version);

	# get file paths
	my $path = $CACHE_ROOT;
	my $key_path	= _get_file_path($key);
	my $cache_file	= $path . '/' . $key_path . $EXT_CACHE;

	# free our files (do it safer for symlinks)
	unlink($cache_file, $cache_file . $EXT_TS);
	if (-e $cache_file . $EXT_DIDX)
	{
		my $dst = readlink($cache_file . $EXT_DIDX);
		unlink($dst)
			if ($dst && substr($dst, 0, length($path)) eq $path);
		unlink($cache_file . $EXT_DIDX);
	}
	core::fs::make_path4file($cache_file) || return 0;

	# check data hash index
	my $didx_file;
	if (ref($data) eq 'SCALAR' && core::conf::get('cache.fs.didx.enable', 1))
	{
		my $didx_path	= _get_file_path(sha1_hex(encode_utf8($$data)));
		$didx_file	= $path . '/.didx/' . $didx_path . $EXT_DIDX;

		# didx file exists
		if (-e $didx_file)
		{
			my $dest = readlink($didx_file);

			# unlink invalid didx file
			if (-e $dest)
			{
				# make links
				link($dest, $cache_file);
				goto WRITE_TS;
			}
			unlink($didx_file);
		}
	}

	# cache data
	my $f;
	return core::log::error('ERROR', "Can not write cache to '$cache_file' - $!", 0)
		if (!open($f, ">", $cache_file));
	binmode($f, ':utf8');
	store_fd($data, *$f);
	close($f);

WRITE_TS:
	# save timefile
	return core::log::error('ERROR', "Can not write cache opts to '" . $cache_file . $EXT_TS . "' - $!", 0)
		if (!open(F, ">", $cache_file . $EXT_TS));

	# complete timestamp
	$timestamp = time()
		if ($timestamp == -1);

	printf F ("%ld %ld ver:%s\n", $expire, $timestamp, $version);
	close(F);

	# create didx
	if (defined($didx_file) && core::fs::make_path4file($didx_file))
	{
		symlink($cache_file, $didx_file);
		symlink($didx_file, $cache_file . $EXT_DIDX);
	}
DONE:
	return 1;
}

# invalidate($key)
sub invalidate($)
{
	my ($key) = @_;

	core::log::SYS_CALL("%s", $key);

	# get file paths
	my $path = $CACHE_ROOT;
	my $key_path	= _get_file_path($key);
	my $cache_file	= $path . '/' . $key_path . $EXT_CACHE;

	# free our files (do it safer for symlinks)
	unlink($cache_file, $cache_file . $EXT_TS);
	if (-e $cache_file . $EXT_DIDX)
	{
		my $dst = readlink($cache_file . $EXT_DIDX);
		unlink($dst)
			if (substr($dst, 0, length($path)) eq $path);
		unlink($cache_file . $EXT_DIDX);
	}

	return 1;
}

# fetch($key [, $timestamp, $version ]) : $data
sub fetch($;$$)
{
	my ($key, $timestamp, $version) = @_;

	core::log::SYS_CALL("%s, %d, %s", $key, $timestamp, $version);

	# check validity (if required)
	my $path = $CACHE_ROOT;
	my $cache_file = $path . '/' . _get_file_path($key) . $EXT_CACHE;
	if (!core::conf::get('cache.noexpire', 0)
		&& defined($timestamp) && $timestamp != -1)
	{
		my $cache_valid = _ts_read($cache_file . $EXT_TS);

		return undef
			if (!defined($cache_valid)
				|| $cache_valid == 0 || $cache_valid <= $timestamp);
	}

	# use cache
	my $dat = core::lru::get($CACHE, $key);

	return $dat
		if (defined($dat));

	# check magic
	return undef
		if (! -r $cache_file || !file_magic($cache_file));

	# try to open file
	my $f;
	return undef
		if (!open($f, $cache_file));

	binmode($f, ':utf8');
	my $ret = fd_retrieve(\*$f);
	close($f);

	# cache data
	core::lru::set($CACHE, $key, $ret, core::conf::get('cache.fs.lru-size', 10));
	return $ret;
}

# attrib($key) : \%attributes
sub attrib($)
{
	my ($key) = @_;
	my $time_file = _get_file_path($key);

	my @ts = _ts_read($time_file);
	return undef
		if (!@ts);
	return {
		'expire' 	=> $ts[0],
		'timestamp'	=> $ts[1],
		'version'	=> $ts[2],
	};
}

# init()
sub init()
{
	# get conf
	$CACHE_ROOT = core::conf::get('cache.fs.root');
	$CACHE_DIR = core::conf::get('cache.fs.dir', 'etlcache');

	# use env
	if (!defined($CACHE_ROOT) && exists($ENV{'ETL_CACHE_FS_ROOT'})) {
		$CACHE_ROOT = $ENV{'ETL_CACHE_FS_ROOT'};
	}
	# user tmp
	elsif (exists($ENV{'HOME'}) && defined($ENV{'HOME'}) && -d $ENV{'HOME'} . '/tmp') {
		$CACHE_ROOT = $ENV{'HOME'} . '/tmp/' . $CACHE_DIR;
	}
	# sys tmp
	else {
		$CACHE_ROOT = '/tmp/' . $CACHE_DIR;
	}

	# log
	core::log::PKG_MSG(LOG_INFO, " CACHE_ROOT = %s", $CACHE_ROOT);
	return 1;
}

1;
