# convert::unknown.pm
#
# Convert from unknown data type
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::unknown;

use strict;
use warnings;

use Data::Dumper;
use XML::LibXML;

# internal
use core;
use core::log;
use core::xml;
use core::mime;

our %CT_MAP = (
	'text/xml' =>
		sub { my $str = substr($_[0], 0, 50);
			($str =~  /^<\?xml\s+version="[[:digit:]\.]+"(\s+.*?)?\?>/om) 
				|| ($str =~ /^\s*<\w+(:\w+)?(\s+>|\s+|>)/om)
				|| ($str =~ /^\s*<!--/om) },
	'application/pdf' =>
		sub { substr($_[0], 0, 10) =~ /^%PDF-\d.\d/o; },
	'application/json' =>
		sub { substr($_[0], 0, 10) =~ /^\[{/o && substr($_[0], -10) =~ /}\]$/o },
);

sub to($)
{
	die(__PACKAGE__ . '::to() - can not convert this way');
	return undef;
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s)", $reqid, $url || core::NULL_URL);

	# try match
	foreach my $ct (keys(%CT_MAP))
	{
		return ($data, $ct)
			if ($CT_MAP{$ct}->($$data, $url));
	}

	# try mime lib
	my $mime = core::mime::getDataType($$data);
	return ($data, $mime)
		if (defined($mime) || $mime);

	# fail
	return ({ msg => 'could not identify content type' }, core::CT_ERROR);
}

1;
