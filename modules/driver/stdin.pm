# driver::stdin.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::stdin;

use strict;
use warnings;

use Data::Dumper;

use core;
use core::log;
use core::url;

## NAMESPACE: $MODULE, URL: $NAMESPACE_URL
our $MODULE = 'stdin';
our $NAMESPACE_URL = core::NAMESPACE_BASE_URL . '/stdin';

# fetch
sub process($$$%)
{
	my ($reqid, $doc, $req, %params) = @_;
	core::log::SYS_CALL("%s, <DOC>, 0x%p", $reqid, $req);

	my ($resp, $nod) = core::create_response($reqid, $MODULE);

	# get location
	if (ref($req) ne 'url')
	{
		# parse
		$req = core::url::parse(core::xml::nodeValue($req));
	}

	# debug
	core::log::PKG_MSG(LOG_NOTICE, " - openning <stdin>");

	# read file
	my $cont = _read_file(*STDIN);
	core::add_data_content($nod, $cont, encode_auto => 1, uri => $req->{href});

	# attribs
	core::set_attrib($nod, core::ATTR_CONTENT_TYPE, core::UNKNOWN_MIME);
	return ($resp, core::UNKNOWN_MIME);
}

sub _read_file($)
{
	# read now
	my ($ret, $lin) = ('');

	binmode($_[0]);
	while(sysread($_[0], $lin, core::SYS_BUFSIZE)) {
		$ret .= $lin;
	}
	return $ret;
}

1;
