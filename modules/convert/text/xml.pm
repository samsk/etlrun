# convert::text::xml.pm
#
# Convert message xml string to xml
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::xml;

use strict;
use warnings;

#use Data::Dumper;
use XML::LibXML;

# internal
use core;
use core::log;
use core::xml;

sub to($)
{
	return undef;
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	my ($doc, $msg) = core::xml::parse($$data, $url);
	return ({ msg => $msg }, core::CT_ERROR)
		if (!$doc);

	# replace data
	$$data = $doc->documentElement();
	return ($$data, core::CT_OK);
}

1;
