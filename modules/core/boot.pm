# core::boot.pm
#
# Bootstraping module
#
# Copyright: Samuel Behan (c) 2014-2016
#
package core::boot;

use strict;
use warnings;

use XML::LibXML qw(:all);
#use Data::Dumper;

$! = 1;

use core;
use core::log;
use core::session;

# process
sub xml_entity_handler($$)
{
	my ($systemId, $publicId) = @_;

	core::log::SYS_CALL("'%s', '%s'", $systemId, $publicId);

	# check if not cached
	my $dat = core::session::cache('xml:entity', $systemId);
	if (defined($dat))
	{
		core::log::SYS_RESOURCE(" - using cached data for entity '%s'", $systemId);
		return $dat;
	}

	# external entities disabled
	my ($resp, %attr) = eval { core::kernel::process('xml:entity', undef, $systemId, -strict => 1); };
	if (!$resp || core::get_error($resp))
	{
		core::log::SYS_RESOURCE("failed to load external entity '%s'", $systemId);
		core::log::dump(LOG_DETAIL, "external entity", $resp);
		return '';
	}

	# we need string
	my $root = $resp->documentElement();
	my $str = $root->firstChild()->toString();

	# cache static content
	core::session::cache('xml:entity', $systemId, $str)
		if (core::is_static($root));

	# back
	return $str;
}

XML::LibXML::externalEntityLoader(\&xml_entity_handler);

1;
