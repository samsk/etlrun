# driver::url.pm
# - url based fetching
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::url;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::url;
use core::xml;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'url';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/url';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my $url = core::xml::nodeValue($req);
	die(__PACKAGE__ . ": no URL defined")
		if (!$url);

	# use url attributes as params
	my (@attribs) = $req->attributes();
	foreach my $attr (@attribs)
	{
		next
			if (ref($attr) ne 'XML::LibXML::Attr' || $attr->namespaceURI());

		$params{ $attr->nodeName() } = $attr->value();
	}

	# process
	my $resp = core::kernel::process($reqid, $doc, $url, %params);
	return ($resp, core::CT_OK);
}

1;
