# driver::group::replicator.pm
# - request grouping with request replicator
#
# Copyright: Samuel Behan (c) 2011-2018
#
package driver::group::replicator;

use strict;
use warnings;

use XML::LibXML;

use core;
use core::log;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'group::replicator';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/group/replicator';

# 
sub _process_subreq($$$%) {
	my ($root, $reqid, $doc, $nod, %params) = @_;

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

	return $dat;
}


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

		my $template_node = $nod;
		my ($replace_node) = core::findnodes($template_node, '//*[@gr:replace = 1][1]',
			'gr' => $NAMESPACE_URL);

		# protect loop
		do {
			my $dat = _process_subreq($root, $reqid, $doc, $nod, %params);

			$nod = undef;
			if ($dat && $replace_node) {
				my ($replacement) = core::findnodes($dat, '//gr:replacement',
					'gr' => $NAMESPACE_URL);

				if ($replacement) {
					# clone parent & direct child
					my $new = $replace_node->parentNode()->cloneNode(1);
					my ($repl) = core::findnodes($new, '//*[@gr:replace = 1][1]',
						'gr' => $NAMESPACE_URL);

					# replace
					$replacement->firstChild()->setAttributeNS($NAMESPACE_URL, 'gr:replace', 1);
					my $replaced = $repl->replaceNode($replacement->firstChild());

					# loop duplicate node
					$nod = $template_node;
				}
			}
		} while ($nod);
		$nod = $template_node;
	}
	return ($resp, core::CT_OK);
}

1;
