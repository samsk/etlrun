# core::json.pm
#
# JSON manipulation functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::json;

use strict;
use warnings;

use JSON;
#use JSON::XS;
#use Data::Dumper;

sub parse(\$;%)
{
	my ($data, %opts) = @_;

	return JSON::from_json($$data, {utf8 => 0});
}

sub isBool(\$)
{
	my ($val) = @_;

	return JSON::is_bool($$val);
}

1;
