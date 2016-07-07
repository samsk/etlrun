# convert::application::pdf.pm
#
# Convert pdf to xml
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::application::pdf;

use strict;
use warnings;

#use Data::Dumper;
use IPC::Open2;

# internal
use core;
use core::log;
use core::xml;
use core::convert;

our $CONF = {
	plugin		=> core::conf::get('convert.text.pdf.plugin', 'pdf2htmlEX'),
};


sub to($)
{
	return undef;
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	# use plugin
	my ($ok, @result) = core::convert::pluginize(__PACKAGE__, $CONF->{'plugin'}, $data, $url, $reqid);
	return @result
		if (!$ok);

	# replace data
	$$data = $result[0]->documentElement();
	return ($$data, core::CT_OK);
}

1;
