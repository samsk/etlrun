# core::fs.pm
#
# Filesystem manipulation functions
#
# Copyright: Samuel Behan (c) 2014-2016
#
package core::fs;

use strict;
use warnings;

#use Data::Dumper;

use core::log;
use core::crypt;

# make_path4file($filename)
sub make_path4file($)
{
	my $file = shift;

	# file exists
	return 1
		if (-f $file);

	# split
	my @arr = split(/\//o, $file);

	# remove filename
	pop(@arr);

	# skip check for existing dir
	$file = join('/', @arr);
	return 1
		if (-d $file);

	$file = shift(@arr);
	foreach my $part (@arr)
	{
		next if ($part eq '');
		$file .= '/' . $part;
		next
			if (-d $file);
		core::log::error('FATAL', "Failed to create directory '$file' - $!")
			if (!mkdir($file));
	}
	return 1;
}

# temp_filename($filename)
sub temp_filename($) {
	my ($file) = @_;

	my $fn;
	while (1) {
		my $rand = core::crypt::rand() * 10000000;
		my $pfix = substr(sprintf('%x', $rand), 0, 6);

		$fn = $file . '.' . $pfix;
		last if (!-e $fn);
	}
	return $fn;
}

1;
