# convert::application::csv.pm
#
# Convert csv to xml
#
# Copyright: Samuel Behan (c) 2017-2018
#
package convert::text::csv;

use utf8;
use strict;
use warnings;

use Text::CSV;
use Data::Dumper;
#use Encode qw(is_utf8 encode);

# internals
use core;
use core::log;
use core::xml;
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

	my $csv = Text::CSV->new({ binary => 1, sep => ';' });

	my $fh;
	my $bytes = $data;
	utf8::encode($bytes);

	open($fh, '<:utf8', \$bytes) || die("$!");

	my $res = [];
	while (my $row = $csv->getline($fh)) {
		my $rec = {};
		for (my $ii = 0; $ii <= $#$row; $ii++) {
			$rec->{'f' . ($ii + 1)} = $$row[$ii];
		}
		push(@$res, $rec);
	}
	close($fh);

	return $res;
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	my $recs = _convert($reqid, $$data);
	return ({ msg => "failed to convert data from csv" }, core::CT_ERROR)
		if (!defined($recs));

	# convert to json version 2
	my ($doc, $nod) = core::xml::create_document('csv');
	$nod->setAttribute('version', '1');
	core::struct::struct2xml($recs, $nod, $doc);

	# replace data
	$$data = $nod;
	return ($$data, core::CT_OK);
}

1;

