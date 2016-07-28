# core.pm
#	- defines basic document structures
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core;

use strict;
use warnings;

use Carp;
use URI::Escape;
use XML::LibXML;
use Data::Dumper;

# NAMESPACE: core::NAMESPACE, URL: core::NAMESPACE_URL
use constant NAMESPACE			=> 'etl';
use constant NAMESPACE_BASE_URL		=> 'http://etl.dob.sk';
use constant NAMESPACE_URL		=> NAMESPACE_BASE_URL . '/etl';
use constant UNKNOWN_MIME		=> 'unknown';
use constant NULL_URL			=> '???';
use constant CT_OK			=> 'etl/ok';
use constant CT_ERROR			=> 'etl/error';
use constant CT_NULL			=> 'etl/null';
use constant RESPONSE_NULL		=> \{};
use constant NS_DEFAULT			=> '_DEF_';

# attributes
use constant ATTR_ID		=> 'id';
use constant ATTR_TIMESTAMP	=> 'ts';
use constant ATTR_EXPIRES	=> 'ets';
use constant ATTR_CONTENT_TYPE	=> 'ct';
use constant ATTR_CONTENT_TYPE_ORI	=> '_ct';
use constant ATTR_FORCE_CTYPE	=> 'force-content-type';
use constant ATTR_SOURCE	=> 'src';
use constant ATTR_FORWARD	=> 'fwd';
use constant ATTR_NOREFETCH	=> 'norefetch';
use constant ATTR_CACHE		=> 'cache';
use constant ATTR_CACHE_ID	=> 'cache_id';
use constant ATTR_IS_CACHED	=> '_cached';
use constant ATTR_ITERATOR	=> 'iterator';
use constant ATTR_NOCACHE	=> 'nocache';
use constant ATTR_LOOPBACK	=> 'loopback';
use constant ATTR_NOATTACHMENT	=> 'noattachment';
use constant ATTR_NOEXEC	=> 'noexec';
use constant ATTR_DRIVER	=> 'driver';
use constant ATTR_MIME_ENCODING	=> 'mime_enc';
use constant ATTR_IS_STATIC	=> 'static';
use constant ATTR_NOCONVERT	=> 'noconvert';

# WORK
use constant SYS_BUFSIZE	=> 8096;

use core::xml;
use core::encode;

# backtrace errors
$SIG{ __DIE__ } = sub {
	if("@_" =~ /line \d+\.$/o)
	{	print STDERR "@_\n";	}
	else
	{	Carp::confess(@_) 	}
};

# create_response($reqid, $module)
sub create_response($$)
{
	my ($reqid, $module) = @_;

	# create document
	my ($resp, $root) = core::xml::create_document('data', core::NAMESPACE, core::NAMESPACE_URL);
	$root->setAttributeNS(core::NAMESPACE_URL, '_driver', $module);
	$root->setAttributeNS(core::NAMESPACE_URL, 'reqid', $reqid);
	return ($resp, $root);
}

# create_response_copy($resp)
sub create_response_copy($)
{
	my ($resp) = @_;

	# get original data
	my $data = core::findnodes($resp, core::NAMESPACE . ':data');
	return _error(1, 'argument is not a response')
		if($data->size() != 1);

	# response root
	my ($resp_root) = $data->get_nodelist();

	# get attribs
	my $attrs = core::findnodes($resp_root, '@' . core::NAMESPACE . ':*');

	my $reqid = $resp_root->getAttributeNS(core::NAMESPACE_URL, 'reqid');
	my $driver = $resp_root->getAttributeNS(core::NAMESPACE_URL, core::ATTR_DRIVER);
	my ($resp2, $root) = create_response($reqid, $driver || 'unknown');

	# copy attributes
	for(my $i = 0; $i < $attrs->size(); $i++)
	{
		my $node = $attrs->get_node($i);;

		next if($node->namespaceURI() ne core::NAMESPACE_URL);
		$root->setAttributeNS(core::NAMESPACE_URL, $node->getName(), $node->getValue());
	}

	# copy uris
	$root->setBaseURI($resp_root->baseURI())
		if($resp_root->baseURI());
	$resp2->setURI($resp->URI())
		if($resp->URI());
	return ($resp2, $root);
}

# raise_error($reqid, $module, $code, %params)
sub raise_error($$$;%)
{
	my ($reqid, $module, $code, %params) = @_;
	my @cal = caller;

	# code as param
	if(!$code && exists($params{'_code'}))
	{
		$code = $params{'_code'};
		delete($params{'_code'});
	}

	# create node
	my $node = new XML::LibXML::Element('err');
	$node->setNamespace(core::NAMESPACE_URL, core::NAMESPACE, 1);
	$node->setAttributeNS(core::NAMESPACE_URL, 'reqid', $reqid);
	$node->setAttributeNS(core::NAMESPACE_URL, core::ATTR_DRIVER, $module);
	$node->setAttributeNS(core::NAMESPACE_URL, 'code', $code);
	$node->setAttributeNS(core::NAMESPACE_URL, core::ATTR_NOEXEC, 1);
	$node->setAttributeNS(core::NAMESPACE_URL, core::ATTR_NOCACHE, 1);
	$node->setAttributeNS(core::NAMESPACE_URL, 'source', $cal[1] . ':' . $cal[2])
		if(@cal);

	foreach my $key (keys(%params))
	{
		next if(!defined($params{$key}));
		my $sref = ref($params{$key});

		# add attribute
		my $nam = $key;
		if($nam =~ s/\@//g && !$sref)
		{
			$node->setAttribute($nam, $params{$key});
			next;
		}

		# add element
		my $n = new XML::LibXML::Element($key);
		$n->setNamespace(core::NAMESPACE_URL, core::NAMESPACE, 1);
		if($sref eq 'XML::LibXML::Error')
		{
			my $str = $params{$key}->dump();
			$str =~ s/^.*?\s=\s//o;
			$str =~ s/;\s*\n$//o;
			$n->addChild(new XML::LibXML::CDATASection($str));
			$n->setAttribute('level', $params{$key}->level());
		}
		elsif($sref =~ /^XML::LibXML/o)
		{
			my $root = $params{$key};
			$root = $root->ownerDocument()
				if($key eq '_fatal'
					&& ref($root) eq 'XML::LibXML::Node'
					&& $root->ownerDocument());
			$root = $root->documentElement()
				if(ref($root) eq 'XML::LibXML::Document'
					&& $root->documentElement());
			if($key eq '_fatal' && defined($root))
			{
				$root->setAttributeNS(core::NAMESPACE_URL, core::ATTR_NOCACHE, 1);
				$root->setAttributeNS(core::NAMESPACE_URL, core::ATTR_CONTENT_TYPE, core::CT_ERROR);
				next;
			}
			$n->appendChild($root->cloneNode(1));
		}
		elsif($sref eq 'ARRAY')
		{
			foreach (@{$params{$key}})
			{
				my $nn = $n->cloneNode(1);
				my $str = Dumper($_);
				$str =~ s/^.*?\s=\s//o;
				$str =~ s/;\s*\n$//o;
				$nn->addChild(new XML::LibXML::CDATASection($str));
				$node->appendChild($nn);
			}
			$n = undef;
			next;
		}
		elsif($sref)
		{
			my $str = Dumper($params{$key});
			$str =~ s/^.*?\s=\s//o;
			$str =~ s/;\s*\n$//o;
			$n->addChild(new XML::LibXML::CDATASection($str));
		}
		else
		{
			$n->addChild(new XML::LibXML::CDATASection($params{$key}));
		}
		$node->addChild($n);
#		warn("core::raise_error: failure to add info element '$nam' - '$@' !\n")
#			if($@);
	}
	return $node;
}

# findnodes($document, $xpath [, %namespaces ]): nodelist
my (%findnodes_NS_CACHE, %findnodes_NS_EXP);
sub findnodes($$;%)
{
	my ($doc, $xpath, %nss) = @_;

	# cache xpath context
	my ($key1, $key2) = (join('-', keys(%nss)), join('-', values(%nss)));
	if(!exists($findnodes_NS_CACHE{$key1}) || !exists($findnodes_NS_CACHE{$key1}->{$key2}))
	{
		my $xc = XML::LibXML::XPathContext->new();
		$xc->registerNs(core::NAMESPACE, core::NAMESPACE_URL);
		foreach $_ (keys(%nss))
		{
			$xc->registerNs($_, $nss{$_})
				if($_ ne core::NAMESPACE && $nss{$_} ne core::NAMESPACE_URL);
		}
		$findnodes_NS_CACHE{$key1}->{$key2} = $xc;
	}
	$findnodes_NS_EXP{$xpath} = XML::LibXML::XPathExpression->new($xpath)
		if(!exists($findnodes_NS_EXP{$xpath}));

	# exec
#	$findnodes_NS_CACHE{$key1}->{$key2}->setContextNode($doc);
	return $findnodes_NS_CACHE{$key1}->{$key2}->findnodes($findnodes_NS_EXP{$xpath}, $doc);
}

# get_uri($node)
sub get_uri($)
{
	my ($node) = @_;

	return uri_unescape($node->baseURI());
}

# set_uri($node, $newURI)
sub set_uri($$)
{
	my ($node, $uri) = @_;

	return $node->setBaseURI($uri);
}

# _encode_data($data [, $mime ]): ($encoded_data, $mime)
sub _encode_data(\$;$)
{
	my ($data, $mime) = @_;

	# FIXME: use core::encode instead of this
	if(!defined($mime) || $mime eq 'base64' || $mime eq '1')
	{
		$mime = 'base64';
		$data = core::encode::base64_encode($$data);
	}
	else
	{
		$mime = undef;
		$data = undef;
	}
	return wantarray ? ($data, $mime) : $data;
}

# decode_data($data, $mime): $decoded_data
sub _decode_data(\$$)
{
	my ($data, $mime) = @_;

	if(!defined($mime) || $mime eq 'base64')
	{
		return core::encode::base64_decode(($$data));
	}
	return undef;
}

# add_data_content($root, $data, encode => , uri =>): $data_node
#	-- add textual content
sub add_data_content($$%)
{
	my ($root, $data, %opts) = @_;
	my $mime;

	# encode if needed
	($data, $mime) = _encode_data($data, $opts{encode})
		if(exists($opts{encode}) && $opts{encode} && defined($data) && $data);

	# add to document
	$root->addChild(new XML::LibXML::CDATASection($data));

	# set content origin
	set_uri($root, $opts{uri})
		if($root && exists($opts{uri}) && $opts{uri});

	$root->setAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING, $mime)
		if($mime);
	return 1;
}

# replace_data_content($data, $content)
#	-- replace data textual content with (recoded) content
sub replace_data_content($$%)
{
	my ($data, $cont, %opts) = @_;

	my $sref = ref($cont);
	if($sref eq 'XML::LibXML::Document')
	{
		$data->removeAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING);
		$data->removeChildNodes();
		core::xml::moveNode($data, $cont->documentElement());
	}
	elsif($sref eq 'XML::LibXML::Element')
	{
		$data->removeAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING);
		$data->removeChildNodes();
		#$data->appendChild($cont);
		core::xml::moveNode($data, $cont);
	}
	elsif($sref)
	{
		die(__PACKAGE__ . ": dont know how to replace content with '$sref' !");
	}
	else	# partialy decode content
	{
		my $mime = $opts{encode} || $data->getAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING);

		# get cdata node
		my $node = $data->firstChild();
		die(__PACKAGE__ . ": trying to replace data content, but DATA child is not a CDATA section !")
			if(!$node || ($node->nodeType() != XML_CDATA_SECTION_NODE
				&& $node->nodeType() != XML_TEXT_NODE));

		# encode if needed
		($cont, $mime) = _encode_data($cont, $mime)
			if($mime && defined($cont) && $cont);

		# replace
		$node->setData($cont);
		$data->setAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING, $mime)
			if($mime);
	}
	return 1;
}

my $get_xpath_ctx_CACHE;
# get_xpath_ctx
sub get_xpath_ctx($)
{
	$get_xpath_ctx_CACHE =  XML::LibXML::XPathContext->new()
		if(!defined($get_xpath_ctx_CACHE));
	$get_xpath_ctx_CACHE->setContextNode($_[0]);
	return $get_xpath_ctx_CACHE;
}

# get_data($document)
sub get_data($)
{
	return get_xpath_ctx($_[0])->findnodes(core::NAMESPACE . ':data');
}

# get_data_root($document)
sub get_data_root($)
{
	return get_xpath_ctx($_[0])->findnodes(core::NAMESPACE . ':data/*[1]');
}

# get_content($data)
sub get_content($)
{
	my $fc;

#	return $_[0]->textContent();
	return $fc->nodeValue()
		if(($fc = $_[0]->firstChild()) && !$fc->nextSibling());
	return  $_[0]->findvalue('text()');
}

# get_data_content($document [, $data, $no_decode ])
#	-- get data textual content (raw / non-xml)
sub get_data_content($;$$)
{
	my ($doc, $data, $no_decode) = @_;

	# get data
	$data = get_data($doc)
		if(!defined($data));
	return undef
		if(!defined($data));

	# stringify
	my $cont = get_content($data);
	return wantarray ? (undef, $data) : undef
		if(!defined($cont));

	# avoid decode
	if(!$no_decode && $cont)
	{
		my $mime = $data->getAttributeNS(core::NAMESPACE_URL, core::ATTR_MIME_ENCODING);

		$cont = _decode_data($cont, $mime)
			if(defined($mime) && $mime ne '');
	}

	return wantarray ? ($cont, $data) : $cont;
}

# get_data_request($node, $namespace [, $localName ])
#	select request element (not having given $namespace but maybe having given $localName)
sub get_data_request($$;$)
{
	my ($node, $namespace, $localName) = @_;

	my $nc = $node->firstChild();
	return undef
		if(!$nc);

	my $req = $nc;
	while(defined($req)
		&& ($req->nodeType() != XML_ELEMENT_NODE
			|| (($req->namespaceURI() && $req->namespaceURI() eq $namespace)
				&& (!defined($localName) || $localName ne $req->localName()))))
	{
		$req = $req->nextSibling();
	}
	return $req || $nc;
}

# get_attrib($node, $attr [, $default]): $value
sub get_attrib($$;$)
{
	my ($root, $attr, $def) = @_;

	my $val = $root->getAttributeNS(core::NAMESPACE_URL, $attr);
	return (defined($val) ? $val : $def);
}

# set_attrib($node, $attr, $value): $boolean
sub set_attrib($$$)
{
	my ($root, $attr, $value) = @_;

	$root->setAttributeNS(core::NAMESPACE_URL, $attr, $value);
	return 1;
}

# del_attrib($node, $attr): $remove
sub del_attrib($$;$)
{
	my ($root, $attr) = @_;

	return $root->removeAttributeNS(core::NAMESPACE_URL, $attr);
}

# get_error($document)
sub get_error($)
{
	my (@list) = get_xpath_ctx($_[0])->findnodes(core::NAMESPACE . ':data/'
		. core::NAMESPACE . ':err'
		. (wantarray ? '' : '[1]'));
	return (wantarray ? @list : $list[0]);
}

# is_static($node)
sub is_static($)
{
	my $node = shift;

	return $node->getAttributeNS(core::NAMESPACE_URL, core::ATTR_IS_STATIC)
		|| $node->getAttributeNS(core::NAMESPACE_URL, core::ATTR_NOEXEC);
}

1;
