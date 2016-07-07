# core::mime.pm
#
# MIME functions
#
# Copyright: Samuel Behan (c) 2013-2016
#
package core::mime;

use strict;
use warnings;

#use Data::Dumper;
use File::LibMagic;

my $LIBMAGIC = File::LibMagic->new();

# text/plain; charset=us-ascii
sub _parse_type($)
{
	my ($type) = @_;

	return wantarray ? ($1, $3) : $1
		if ($type =~ /^(.+?)(;\s*charset=(.*))?$/o);
	die(__PACKAGE__ . ": failed to parse '$type'");
}

# getFileType($filename): ($mime, $charset)
sub getFileType($)
{
	my ($file) = @_;

	return undef
		if (!-r $file);

	my $type = $LIBMAGIC->checktype_filename($file);
	return _parse_type($type);
}

# getDataType($filename): ($mime, $charset)
sub getDataType(\$)
{
	my ($data) = @_;

	my $type = $LIBMAGIC->checktype_contents($$data);
	return _parse_type($type);
}

1;
