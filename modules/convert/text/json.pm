# convert::application::json.pm
#
# Convert json to xml
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::json;

use strict;
use warnings;

use Data::Dumper;
#use Encode qw(is_utf8 encode);

# internals
use core;
use core::log;
use core::xml;
use core::json;
use core::struct;

# globals
my $XML2JSON;

sub to($)
{
	return undef;
}

# convert($reqid, $data)
sub _convert($$)
{
	my ($reqid, $data) = @_;

	return core::json::parse($data);
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	my $recs = _convert($reqid, $$data);
	return ({ msg => "failed to convert data to json" }, core::CT_ERROR)
		if (!defined($recs));

	# convert to json version 2
	my ($doc, $nod) = core::xml::create_document('json');
	$nod->setAttribute('version', '3');
	core::struct::struct2xml($recs, $nod, $doc);

	# replace data
	$$data = $nod;
	return ($$data, core::CT_OK);
}

1;

