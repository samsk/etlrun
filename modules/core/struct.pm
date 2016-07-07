# core::struct.pm
#
# struct manipulation functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::struct;

use strict;
use warnings;

#use Data::Dumper;

use core::xml;
use core::json;

sub _var2xml(\$$$$;$);
sub _var2xml(\$$$$;$)
{
	my ($var, $root, $doc, $map, $noConserve) = @_;

	# nothing to do
	return 1
		if (!defined($$var));

	my $ref = ref($$var);
	if ($ref eq 'ARRAY')
	{
		my $arr = $root;

		if (!$noConserve)
		{
			$arr = $doc->createElement('arr');
			$root->addChild($arr);
		}
		else {
			$root->setNodeName('arr');
		}

		my $ii = 0;
		foreach my $elem (@$$var)
		{
			my $node = $doc->createElement('el');
			$node->setAttribute('no', $ii++);
			$arr->addChild($node);

			_var2xml($elem, $node, $doc, $map, 1);
		}
	}
	elsif ($ref eq 'HASH')
	{
		my $arr = $root;

		if (!$noConserve)
		{
			$arr = $doc->createElement('obj');
			$root->addChild($arr);
		}
		else {
			$root->setNodeName('obj');
		}

		foreach my $elem (keys(%$$var))
		{
			my $node = $doc->createElement('el');
			$node->setAttribute('name', $elem);
			$arr->addChild($node);

			_var2xml($$var->{$elem}, $node, $doc, $map, 1);
		}
	}
	# TODO: XML classes handling needed !
	else
	{
		my $node = $root;
		my $val = $$var;

		if (!$noConserve)
		{
			$node = $doc->createElement('el');
			$root->addChild($node);
		}

		# specialized JSON bool handling
		$val = ($val eq $JSON::true) ? 1 : 0
			if (core::json::isBool($val));

		if (core::xml::needsCDATA($val)) {
			$node->addChild(new XML::LibXML::CDATASection($val));
		}
		else {
			$node->appendText($val);
		}
	}
	return 1;
}

# struct2xml($struct, $node, $doc [, $map])
#	convert perl data structure to stable XML representation
sub struct2xml($$$;$)
{
	my ($struct, $node, $doc, $map) = @_;
	$doc = $node->getDocument()
		if (!defined($doc));

	_var2xml($struct, $node, $doc, $map);
	return 1;
}


1;

