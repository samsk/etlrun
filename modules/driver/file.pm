# driver::file.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::file;

use strict;
use warnings;

use File::Spec;
use XML::LibXML;
use Data::Dumper;

use core;
use core::log;
use core::url;
use core::xml;
use core::session;
use driver::stdin;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'file';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/file';

# fetch
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# get location
	my ($loc);
	if (ref($req) eq 'url')
	{	$loc = $req->{loc};		}
	else
	{
		# got XML request
		my $url = core::xml::nodeValue($req);

		# parse
		$req = core::url::parse($url);
		$loc = $req->{loc};
	}

	# find file now
	my $file = core::conf::data($loc);
	goto ERROR
		if (!defined($file));

	# get absolute path
	$file = File::Spec->rel2abs($file);

	# try cache
	my ($cont, @stat, $entry);
	$entry = core::session::cache(__PACKAGE__, $file)
		if (defined($file) && core::conf::get('driver.file.session-cache', 1));
	if (defined($entry))
	{
		$cont = $entry->{c};
		@stat = @{ $entry->{s} };
		core::log::PKG_MSG(LOG_NOTICE, " - using cached file '%s'", $file);
		goto DONE;
	}

	core::log::SYS_RESOURCE(" - openning file '%s'", $file || '');

	# try open
	goto ERROR
		if (! -r $file || !open(F, $file));

	# read file
	@stat = stat(F);
	$cont = driver::stdin::_read_file(*F);

	# cache
	core::session::cache(__PACKAGE__, $file, { c => $cont, s => \@stat })
		if (core::conf::get('driver.file.session-cache', 1));

DONE:
	# add content
	core::add_data_content($nod, $cont, encode_auto => 1, uri => $req->{href});

	# attribs
	core::set_attrib($nod, core::ATTR_SOURCE, $file);
	core::set_attrib($nod, core::ATTR_TIMESTAMP, $stat[9]);
	core::set_attrib($nod, core::ATTR_CONTENT_TYPE, core::UNKNOWN_MIME);
	core::set_uri($resp, $req->{href});
	# XXX: maybe we should avoid setting static content if some url param/query is present
	core::set_attrib($nod, core::ATTR_IS_STATIC, 1);
	return ($resp, core::UNKNOWN_MIME);

ERROR:
	$nod->addChild(core::raise_error($reqid, $MODULE, 404,
			_fatal => $resp,
			req => $req,
			msg => 'NOT FOUND: ' . $!,
			url => $loc,
			file => $file,
			path => join(':', core::conf::data_path())));
	return ($resp, core::CT_ERROR);
}

1;
