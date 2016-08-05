# driver::file::writer::simple.pm
#
#
# Copyright: Samuel Behan (c) 2014-2016
#
package driver::file::writer::simple;

use strict;
use warnings;

use Data::Dumper;
use XML::LibXML;

use core;
use core::fs;
use core::log;
use core::url;
use core::xml;
use core::conf;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'file::writer::simple';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/file/writer/simple';

# _write_file($prefix, $filename, $postfix, $node, $resp, $mkdir, $xml, $noover)
sub _write_file($$$$$$$$)
{
	my ($prefix, $file, $postfix, $node, $resp, $mkdir, $xml, $noover) = @_;

	$file = $prefix . $file . $postfix;

	my $verbose = core::xml::attrib($resp, 'verbose', $NAMESPACE_URL);;

	core::log::PKG_MSG((defined($verbose) ? LOG_ALWAYS : LOG_IMPORTANT), " - writing file '%s'", $file);

	my $fn = $file;
	my $exists = -e $fn;
	return (undef, _code => 405,
			filename => $file,
			error => $!,
			prefix => $prefix,
			postfix => $postfix,
			noclobber => $noover,
			msg => 'NOT ALLOWED: trying to write to an existing file')
		if($noover && $exists);

	# create dir path
	if($mkdir) {
		core::fs::make_path4file($file);
	}

	#TODO: add system limitation on file write access - core::security::verify_file_write()...
	my $fd;
	return (undef, _code => 400,
			filename => $fn,
			prefix => $prefix,
			postfix => $postfix,
			error => $!,
			msg => 'BAD REQUEST: failed to open file for writing')
		if (!open($fd, ">", $fn));
	binmode($fd, ":utf8");

	my $size = 0;
	$size += syswrite($fd, '<?xml version="1.0" encoding="utf-8"?>' . "\n")
		if ($xml);

	# FIXME: handle write errors here !?
	if ($xml)
	{	$size += syswrite($fd, $node->toString());		}
	else
	{	$size += syswrite($fd, core::get_content($node) || $node->textContent());	}

	close($fd);

	# response info
	my $doc = $resp->ownerDocument();
	my $nod = $doc->createElement("file");
	$nod->addChild(new XML::LibXML::CDATASection($fn));
	$nod->setAttribute("update", 1)
		if ($exists);
	$nod->setAttribute("written", $size);
	$nod->setAttribute("xml", $xml || 0);
	$resp->addChild($nod);
	return 1;
}

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# system attribs
	my $sys_noover = core::conf::get('driver.file.writer.noclobber',
			core::conf::get('system.file.noclobber', 0));

	# attribs
	## @multi-file
	my $multi	= core::xml::attrib($req, ['multi-file', 'multi'], $NAMESPACE_URL);
	## @noclobber
	my $noover 	= core::xml::attrib($req, ['noclobber', 'no-clobber', 'no-overwrite'],
			$NAMESPACE_URL, $sys_noover);
	## @prefix
	my $prefix 	= core::xml::attrib($req, 'prefix', $NAMESPACE_URL, '');
	## @postfix
	my $postfix 	= core::xml::attrib($req, 'postfix', $NAMESPACE_URL, '');
	## @file
	my $filename	= core::xml::attrib($req, 'file', $NAMESPACE_URL);
	## @mkdir
	my $mkdirs	= core::xml::attrib($req, 'mkdir', $NAMESPACE_URL);
	## @xml
	my $xml		= core::xml::attrib($req, 'xml', $NAMESPACE_URL);

	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	if (!$multi && !defined($filename))
	{
		$nod->addChild(core::raise_error($reqid, $MODULE, 400,
			_fatal => $resp,
			req => $req,
			msg => 'BAD REQUEST: destination filename not specified',
			filename => $filename));
		return ($resp, core::CT_ERROR);
	}

	# process
	if (!$multi)
	{
		my ($child) = $req->nonBlankChildNodes();

		my ($retval, %info) = _write_file($prefix, $filename, $postfix, $child, $nod,
					$mkdirs, $xml, $noover);
		if (!defined($retval))
		{
			$nod->addChild(core::raise_error($reqid, $MODULE, undef,
				_fatal => $resp,
				req => $req,
				%info));
			return ($resp, core::CT_ERROR);
		}
	}
	else
	{
		my $elem_pos = 0;
		my (@childs) = $req->childNodes();

		foreach my $child (@childs)
		{
			# skip non-elements
			next
				if ($child->nodeType != XML_ELEMENT_NODE);
			$elem_pos++;

			## */@file
			$filename	= core::xml::attrib($child, 'file', $NAMESPACE_URL);

			if (!defined($filename))
			{
				$nod->addChild(core::raise_error($reqid, $MODULE, 400,
					_fatal => $resp,
					req => $req,
					multi => 1,
					element => $elem_pos,
					msg => 'BAD REQUEST: destination filename not specified in multi write node',
					filename => $filename));
				return ($resp, core::CT_ERROR);
			}

			$child->removeAttributeNS($NAMESPACE_URL, 'file');

			my ($retval, %info) = _write_file($prefix, $filename, $postfix, $child, $nod,
						$mkdirs, $xml, $noover);
			if (!defined($retval))
			{
				$nod->addChild(core::raise_error($reqid, $MODULE, undef,
					_fatal => $resp,
					req => $req,
					multi => 1,
					element => $elem_pos,
					%info));
				return ($resp, core::CT_ERROR);
			}
		}
	}
	return ($resp, core::CT_OK);
}

1;
