# core::conf.pm
#
# Configuration module
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::conf;

use strict;
use warnings;

use Cwd;
use File::Spec qw(abs2rel);
#use Data::Dumper;

#TODO: context it via core::context

# flags
my %CONF = ();
my @LIB = ('.');
my @DATA_LIB = ('.');

END { %CONF = (); undef %CONF;
	@LIB = (); undef @LIB;
	@DATA_LIB = (); undef @DATA_LIB; }

# reload time
my $FLAG_RELOAD_TIME = 1;
sub FLAG_RELOAD_TIME(;$)
{
	$FLAG_RELOAD_TIME = $_[0]
		if (defined($_[0]));
	return $FLAG_RELOAD_TIME;
}

# get($key [, $default ]): mixed
sub get($;$)
{
	my ($key, $def) = @_;

	return exists($CONF{ $key }) ? $CONF{ $key } : $def;
}

# set($key, $value)
sub set($$)
{
	my ($key, $val) = @_;

	$CONF{ $key } = $val;
	return;
}

# in_array($key, $value)
sub in_array($$;$)
{
	my ($key, $val, $def) = @_;

	return grep { $_ eq $val } @{ get($key, defined($def) ? $def : []) };
}

# push($key, $value)
sub push($$)
{
	my ($key, $val) = @_;

	::push(@{$CONF{ $key }}, $val);
	return;
}

# _file_find($filename, @path)
sub _file_find($\@)
{
	my ($fn, $path) = @_;

	# find path
	my (@files);
	foreach my $p (@$path)
	{
		my $file = $p . '/'. $fn;

		next
			if (!-e $file);
		return $file
			if (!wantarray);
		::push(@files, $file);
	}
	return wantarray ? @files : undef;
}

# _add_path(\@var, $path_to_ad)
sub _add_path(\@$)
{
	my ($var, $path) = @_;

	$path = sprintf("%s/%s", getcwd(), $path)
		if ($path && $path !~ /^\//o);

	unshift(@$var, File::Spec->rel2abs($path))
		if (defined($path));
	return wantarray ? @$var : $#$var;
}

# file($filename)
sub file($)
{
	return _file_find($_[0], @LIB);
}

# file_path($path)
sub file_path($)
{
	unshift(@INC, $_[0]);
	return _add_path(@LIB, $_[0]);
}

# data($filename)
sub data($)
{
	return _file_find($_[0], @DATA_LIB);
}

# data_path($path)
sub data_path(;$)
{
	return _add_path(@DATA_LIB, $_[0]);
}

1;
