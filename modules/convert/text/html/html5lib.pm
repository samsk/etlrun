# convert::text::html::html5lib.pm
#
# HTML-to-XML parser using HTML::HTML5::Parser module
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::html::html5lib;

use strict;
use warnings;

#use Data::Dumper;
use IO::Handle;
use XML::LibXML;
use HTML::HTML5::Parser;

sub parse($$)
{
	my ($data, $url) = @_;
	my $parser = new HTML::HTML5::Parser();

	# parse
	local $@;
	my $doc = eval { $parser->parse_string($data, { encoding => 'utf-8' }); };
	if (!$doc || $@)
	{
		my @err = $parser->errors();
		return (undef, {
			html5lib => \@err,
			err => $@,
			msg => "HTML parsing failed"	});
	}

	# return parsed document
	return ($doc);
}

1;
