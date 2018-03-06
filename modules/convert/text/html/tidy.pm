# convert::text::html::tidy.pm
#
# HTML-to-XML parser using HTML::Valid module
#
# Copyright: Samuel Behan (c) 2015-2018
#
package convert::text::html::tidy;

use strict;
use warnings;

#use Data::Dumper;
use IO::Handle;
use XML::LibXML;
use HTML::Valid;

my %tidy_opts = (
	'quiet' => 0,
	'show-info' => 0,
	'tidy-mark' => 0,
#	input_encoding => 'utf8',
#	output_encoding => 'utf8',
	'add-xml-decl' => 1,
#	'utf8' => 1,
#	add_xml_space => 1,
	'bare' => 1,
	'doctype' => 'omit',
	'enclose-block-text' => 1,
	'fix-backslash' => 1,
	'fix-uri' => 1,
	'clean' => 0,
	'drop-proprietary-attributes' => 0,
	'numeric-entities' => 1,
	'logical-emphasis' => 0,
	'lower-literals' => 1,
#	'word-2000' => 1,
	'show-warnings' => 0,
	'break-before-br' => 1,
#	'drop-empty-elements' => 1,
#	'drop-empty-paras' => 1,
	'indent' => 0,
	'escape-cdata' => 1,
	'output-xhtml' => 1,
#	'output-xml' => 1,
#	'force-output' => 1,
);

sub parse($$)
{
	my ($data, $url) = @_;
	my $parser = HTML::Valid->new(%tidy_opts);

	# parse
	local $@;
	my ($out, $errors) = eval { $parser->run($data); };
	if (!$out || ($errors && $errors =~ /(\d+)\s+errors/o && $1 > 0))
	{
		return (undef, {
			tidy => $errors,
			err => $@,
			msg => "HTML parsing failed" });
	}

	# parse
	my ($doc, $msg) = core::xml::parse_html($out, $url);

	# FIXME: handle this correctly !
	if (!$doc)
	{
		return (undef, {
			tidy => $errors,
			msg => "tidy HTML parsing failed" });
	}

	# return parsed document
	return ($doc);
}

1;
