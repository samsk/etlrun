# convert::text::javascript.pm
#
# Convert json to xml
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::text::javascript;

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

sub to($)
{
	return undef;
}

# convert($reqid, $data)
sub _convert($$)
{
	my ($reqid, $data) = @_;

	$data	=~ s/\[,/[null,/og;
	$data	=~ s/,,/,null,/og;

	# simple split by ;
	my (@arr, %hash);
	my @data = split(/\s*;[\r\n]+\s*/o, $data);
	foreach my $dat (@data)
	{
		my ($json, $var)= ($dat);

		# get variable if there
		$var = $1
			if ($json =~ s/^([\w\.]+)\s*=\s*//o);

		# parse json
		$json = core::json::parse($json)
			if ($dat =~ /(\[|{)/o);

		# add key to data
		if ($var)
		{	$hash{$var} = $json;	}
		else
		{	push(@arr, $json);	}
	}

	# join
	if (%hash && !@arr) {
		return \%hash;
	}
	elsif (%hash && @arr) {
		return [ \%hash, @arr ];
	}
	elsif ($#arr == 0) {
		return $arr[0];
	}
	else {
		return @arr;
	}
	return undef;
}

sub from($$$;$)
{
	my ($reqid, $data, $url, $params) = @_;
	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	my $recs = _convert($reqid, $$data);
	return ({ msg => "failed to convert data to json" }, core::CT_ERROR)
		if (!defined($recs));

	# convert to json version 2
	my ($doc, $nod) = core::xml::create_document('javascript');
	$nod->setAttribute('version', '2');
	core::struct::struct2xml($recs, $nod, $doc);

	# replace data
	$$data = $nod;
	return ($$data, core::CT_OK);
}

1;
