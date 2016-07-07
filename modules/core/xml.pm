# core::xml.pm
#
# XML helper functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::xml;

use strict;
use warnings;

use XML::LibXML;
#use Data::Dumper;

# create_document([ $node, $ns, $ns_url ])
sub create_document(;$$$)
{
	my ($nod, $ns, $ns_url) = @_;

	my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
	if (defined($nod) && $ns && $ns_url)
	{	$nod = $doc->createElementNS($ns_url, $ns . ':' . $nod);
		$doc->setDocumentElement($nod);		}
	elsif (defined($nod))
	{	$nod = $doc->createElement($nod);
		$doc->setDocumentElement($nod);		}
	return wantarray ? ($doc, $nod) : $doc;
}

# attrib($node, $name, $namespace, $default)
sub attrib($$$;$)
{
	my ($node, $name, $ns, $default) = @_;

	$name = [ $name ]
		if (ref($name) ne 'ARRAY');
	foreach my $nam (@$name)
	{
		my $value = $node->getAttributeNS($ns, $nam)
				|| $node->getAttribute($nam);
		return $value
			if (defined($value));
	}
	return $default;
}

# attribs($node, $namespace, @names)
sub attribs($$\@;$)
{
	return attrib($_[0], $_[2], $_[1], $_[3]);
}

# nodeValue($node)
sub nodeValue($)
{
	my ($obj) = @_;

	my $fc = $obj->firstChild();
	return defined($fc) ? $fc->nodeValue() : undef;
}

# parse($string [, $base_uri_hint, %options ])
sub parse($;$%)
{
	my ($in, $uri, %opts) = @_;

	my $h = new XML::LibXML( no_network => 1,
				line_numbers => 1,
#				recover => 2,
				xinclude => 1,
				no_xinclude_nodes => 1,
				encoding => 'utf-8',
				%opts );

	local $@;
	my $r = eval {
		if (ref($in) eq 'GLOB')
		{	$h->parse_fh($in, $uri || (caller)[1]); }
		else
		{	$h->parse_string($in, $uri || (caller)[1]); }
	};
	return wantarray ? ($r, $@) : $r;
}

# parse_html($string [, $base_uri_hint, %options ])
sub parse_html($;$%)
{
	my ($in, $uri, %opts) = @_;

	my $h = new XML::LibXML(no_network => 1,
				line_numbers => 1,
				recover => 2,
				xinclude => 0,
				no_xinclude_nodes => 1,
				encoding => 'utf-8',
				%opts );

	local $@;
	my $r = eval { $h->parse_string($in, $uri || (caller)[1]); };
	return wantarray ? ($r, $@) : $r;
}

# copyNode($dest_node, @src_nodes)
sub copyNode($@)
{
	my ($dst, @src) = @_;

	my $dst_own = $dst->ownerDocument();
	foreach my $nod (@src)
	{
		$dst->addChild($dst_own->importNode($nod));
#		$dst->appendChild($nod);
#		$nod->unbindNode();
	}
	return 1;
}

# moveNode($dest_node, @src_nodes)
sub moveNode($@)
{
	my ($dst, @src) = @_;

	return copyNode($dst, @src);
}

# getFirstElementChild($node)
sub getFirstElementChild($)
{
	my ($node) = @_;

	my $fc = $node->getFirstChild();
	while (defined($fc))
	{
		return $fc
			if ($fc->nodeType == XML_ELEMENT_NODE);
		$fc = $fc->nextNonBlankSibling();
	}
	return undef;
}

# isXML($obj)
sub isXML($)
{
	return (substr(ref($_[0]), 0, 11) eq 'XML::LibXML');
}

# isDocument($obj)
sub isDocument($)
{
	return (ref($_[0]) eq 'XML::LibXML::Document');
}

# isElement($obj)
sub isElement($)
{
	return (ref($_[0]) eq 'XML::LibXML::Element');
}

# needsCDATA($string)
sub needsCDATA(\$)
{
	my ($str) = @_;

	return ($$str && $$str =~ /[\&\<\>\"\']/o);
}

1;
