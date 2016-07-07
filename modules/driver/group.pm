# driver::group.pm
# - request grouping
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::group;

use strict;
use warnings;

use XML::LibXML;

use core;
use core::log;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'group';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/group';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);

	for (my $nod = $req->firstChild(); defined($nod); $nod = $nod->nextSibling())
	{
		# skip non-elements
		next
			if ($nod->nodeType != XML_ELEMENT_NODE);

		# process
		my $dat = core::kernel::process($reqid, $doc, $nod, %params);
		if ($dat) {	
			foreach my $child ($dat->documentElement()->childNodes()) {
				core::xml::moveNode($root, $child);
			}
		}
		else {
			core::xml::copyNode($root, $nod);
		}
	}
	return ($resp, core::CT_OK);
}

1;
