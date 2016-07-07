# driver::embed.pm
#
#  -- allows in-document resources embedding
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::embed;

use strict;
use warnings;

#use Data::Dumper;

use core;
use core::log;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'embed';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/embed';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my ($resp, $nod) = core::create_response($reqid, $MODULE);
	my $loc = $req->{loc};

	# build xpath req
	my $xpath = sprintf('//embed:embed[@id = \'%s\'][1]/*[1]', $loc);
	my ($data) = core::findnodes($doc, $xpath, $MODULE => $NAMESPACE_URL);

	# FIXME: missing error response
	if (!defined($data))
	{
		$nod->addChild(core::raise_error($reqid, $MODULE, 404,
			_fatal => $resp,
			req => $req,
			msg => 'NOT FOUND: embeded resource not found',
			url => $loc));
		return ($resp, core::CT_ERROR);
	}

	# apped to response
	$nod->appendChild($data);
	return ($resp, core::CT_OK);
}

1;
