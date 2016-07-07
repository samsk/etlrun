# driver::adapt.pm
#  -- document adaptation driver
#
# Copyright: Samuel Behan (c) 2012-2016
#
package driver::adapt;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::xml;
use core::convert;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'adapt';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/adapt';

sub _convert_node($$$$)
{
	my ($reqid, $doc, $node, $instr) = @_;

	my $url = core::get_uri($doc->documentElement());
	my $data = core::get_content($node);

	my $err = core::convert::apply_direct($reqid, $data, $instr->{'content-type'}, $url);
	if (defined($err))
	{
		#FIXME: raise error
		die Dumper($err);
	}

	# replace
	$node->removeChildNodes();
	core::xml::moveNode($node, $data);
	return 1;
}

sub _rename_node($$$$)
{
	my ($reqid, $doc, $node, $instr) = @_;

	$node->setNodeName($instr->{'nodeName'});
	return 1;
}


# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# response
	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# get attributes

	# get req node
	my $req_node = core::get_data_request($req, $NAMESPACE_URL);
	die(__PACKAGE__ . ": request node not found")
		if (!$req_node);

	# get adaptation configs
	my (@instr);
	my (@nodes) = core::findnodes($req, $MODULE . ':*', $MODULE => $NAMESPACE_URL);
	foreach my $nod (@nodes)
	{
		my $conf = {};

		## @select
		$conf->{'xpath'} = core::xml::attrib($nod, 'xpath', $NAMESPACE_URL);
		die(__PACKAGE__ . ": xpath attribute missing")
			if (!defined($conf->{'xpath'}));

		## process
		if ($nod->localName() eq 'convert')
		{
			$conf->{'mode'} = 'convert';
			$conf->{'content-type'} = core::xml::attrib($nod, 'content-type', $NAMESPACE_URL);
			die(__PACKAGE__ . ": content-type attribute missing")
				if (!defined($conf->{'content-type'}));
		}
		## rename
		elsif ($nod->localName() eq 'rename')
		{
			$conf->{'mode'} = 'rename';
			$conf->{'nodeName'} = core::xml::nodeValue($nod);
		}
		else
		{	next;		}

		## @optional
		$conf->{'opt'} = core::xml::attrib($nod, 'optional', $NAMESPACE_URL);

		## @id
		$conf->{'id'} = core::xml::attrib($nod, 'id', $NAMESPACE_URL);

		# add
		push(@instr, $conf);
	}

#	# execute req
	my $data_root = $req_node;
	my $data = core::kernel::process($reqid, $doc, $req_node, %params);
	if ($data)
	{	($data_root) = core::get_data_root($data);	}
	else
	{	$data_root = $req_node;				}

	# adapt now
	foreach my $ins (@instr)
	{
		# build namespace list
		my %ns;
		my (@nslist) = $data_root->getNamespaces();
		foreach my $ns (@nslist)
		{
			$ns{ $ns->declaredPrefix() || core::NS_DEFAULT } = $ns->declaredURI();
		}

		# locate node
		my ($node) = core::findnodes($data_root, $ins->{'xpath'}, %ns);

		# not found & optional => skip
		if (!$node && $ins->{'optional'})
		{	next;	}
		elsif (!$node)
		{
			die(__PACKAGE__ . ": required node not found xpath: $ins->{'xpath'}, op: $ins->{'mode'}");
		}

		if ($ins->{'mode'} eq 'convert')
		{
			_convert_node($reqid, $data, $node, $ins);
		}
		elsif ($ins->{'mode'} eq 'rename')
		{
			_rename_node($reqid, $data, $node, $ins);
		}
		else
		{	die(__PACKAGE__ . ": mode '$ins->{'mode'}' NOT IMPLEMENTED !");	}
	}

	# copy node
	core::xml::moveNode($nod, $data_root);
	return ($resp, core::CT_OK);
}

1;
