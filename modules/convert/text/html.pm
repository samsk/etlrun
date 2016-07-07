# convert::text::html.pm
#
# Convert text to html.
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::html;

use strict;
use warnings;

#use Data::Dumper;
use XML::LibXML;

#internal
use core;
use core::log;
use core::xml;
use core::url;
use core::conf;
use core::convert;

our $CONF = {
	plugin		=> core::conf::get('convert.text.html.plugin', 'tidy'),
};

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	my ($ok, @result) = core::convert::pluginize(__PACKAGE__, $CONF->{'plugin'}, $data, $url);
	return @result
		if (!$ok);
	my $out = $result[0];

	my $set_xhtml = core::conf::get('convert.text.html.xhtml', 0);
	if ($set_xhtml) {
		$out->documentElement()->setNamespace('http://www.w3.org/1999/xhtml', undef, 1);
	} else {
		$out->documentElement()->setNamespaceDeclURI(undef, undef);
	}

	# add html base
	if ($url)
	{
		my $base;
		if ($set_xhtml) {
			($base) = core::findnodes($out->documentElement(), '/xhtml:html/xhtml:head',
					'xhtml' => 'http://www.w3.org/1999/xhtml');
		} else {
			($base) = core::findnodes($out->documentElement(), '/html/head');
		}
		
		if ($base)
		{
			my $node = XML::LibXML::Element->new('base');
			$node->setAttribute('href', $url)
				if (defined($url));
			$base->appendChild($node);
		}
	}


	# replace data
	$$data = $out->documentElement();
	return ($$data, core::CT_OK);
}

1;
