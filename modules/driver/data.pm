# driver::data.pm
# - data driver
#
# Copyright: Samuel Behan (c) 2013-2016
#
package driver::data;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::kernel;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'data';
our $NAMESPACE_URL  = core::NAMESPACE_BASE_URL . '/data';

# process
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	# create response
	my ($resp, $root) = core::create_response($reqid, $MODULE);

	# get location
	my ($data, $mime);
	if (ref($req) eq 'url') {
		$data = $req->{loc};
		## /<mime_enc>/<url>
		$mime = $2
			if ($data =~ s/^\/((\w{0,20})\/)?//o);
	}
	else {
		## /data/@mime_enc
		$mime = $req->getAttribute(core::ATTR_MIME_ENCODING);

		# got XML request
		$data = core::xml::nodeValue($req);
	}

	# decode data by mime
	$data = core::_decode_data($data, $mime);

	# add data
	#$root->append($data);
	core::add_data_content($root, $data);

	# attribs
#	core::set_attrib($root, core::ATTR_SOURCE, $MODULE);
#	core::set_attrib($root, core::ATTR_CONTENT_TYPE, core::UNKNOWN_MIME);
	return ($resp, core::UNKNOWN_MIME);
}

1;
