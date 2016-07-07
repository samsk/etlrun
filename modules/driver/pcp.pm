# driver::pcp.pm
#	- precompiler
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::pcp;

use strict;
use warnings;

use XML::LibXML;

use core;
use core::log;

our $MODULE = 'pcp';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/pcp';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	my ($url, $loc) = ($req->{href}, $req->{loc});
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# find nodes to be precompiled
	my $data = core::findnodes($req, "//*[@$MODULE:compile]");

	# process them
	foreach my $node ($data->get_nodelist())
	{
		my $cmode = $node->getAttributeNS($NAMESPACE_URL, 'compile');
		my $new_node;

		if ($cmode eq '2')
		{
			$new_node = core::kernel::process($reqid, undef, $node->string_value(), -norefetch => 1);
		}
		else
		{
			die("not implemented");
		}

		# replace child
		$node->parentNode()->insertAfter($new_node->documentElement()->firstChild(), $node);
		$node->parentNode()->replaceChild(new XML::LibXML::Comment($node->toString()), $node);
	}

	return ($req, core::CT_OK);
}

1;
