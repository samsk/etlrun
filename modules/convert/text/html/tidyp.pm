# convert::text::html::tidy.pm
#
# HTML-to-XML parser using HTML::Tidy module
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::html::tidyp;

use strict;
use warnings;

#use Data::Dumper;
use HTML::Tidy;

use core::log;
use core::xml;

my %tidy_opts = (
	tidy_mark => 0,
	input_encoding => 'utf8',
	output_encoding => 'utf8',
	add_xml_decl => 1,
#	add_xml_space => 1,
	bare => 1,
	doctype => 'omit',
	enclose_block_text => 1,
	fix_backslash => 1,
	fix_uri => 1,
	clean => 0,
	drop_proprietary_attributes => 0,
	numeric_entities => 1,
	logical_emphasis => 0,
	lower_literals => 1,
	word_2000 => 1,
	show_warnings => 0,
	break_before_br => 1,
	indent => 0,
#	escape_cdata => 1,
	output_xhtml => 1
);

sub parse($$)
{
	my ($data, $url) = @_;
	my $tidy = new HTML::Tidy(\%tidy_opts);

	$tidy->ignore( type => TIDY_INFO );
	$tidy->ignore( type => TIDY_WARNING );
	#$tidy->ignore( type => TIDY_ERROR );

	# tidy clean
	my $cont = $tidy->clean($data);
	if (!$cont || $tidy->messages)
	{
		my @tid = $tidy->messages();

		# filter ignorables
		my @tid2;
		foreach (@tid)
		{
			if (!($_->type() == 3 && $_->text() =~ /is not recognized/o))	{	
				push(@tid2, $_);
			} else	{
				core::log::PKG_MSG(LOG_WARNING, " - ignoring tidy error (%d) '%s' in doc %s",
					$_->type(), $_->text(), $url || '???');
			}
		}

		# non-ignored tidy error
		if (!$cont || @tid2) {
			return (undef, {
				tidy => \@tid2,
				msg => "HTML tidying failed" });
		}
	}

	# parse
	my ($doc, $msg) = core::xml::parse_html($cont, $url);

	# FIXME: handle this correctly !
	if (!$doc)
	{
		my @tid = $tidy->messages;
		return (undef, {
			tidy => \@tid,
			msg => "tidy HTML parsing failed"	});
	}

	# return parsed document
	return ($doc);
}

1;
