# convert::application::pdf::pdftohtml.pm
#
# Convert pdf to xml via pdftohtml
#
# Copyright: Samuel Behan (c) 2011-2016
#
package convert::application::pdf::pdftohtml;

use strict;
use warnings;

#use Data::Dumper;
use IPC::Open2;

# internal
use core;
use core::log;
use core::xml;

sub parse($$)
{
	my ($data, $url) = @_;
#	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	# pipe pdftohtml
	my ($fin, $fout);
	my $pid = open2($fout, $fin, "/usr/bin/pdftohtml", "-xml", "-stdout", "-", "DATA");
	my $retval = $?;

	return (undef, {
		msg => "failed to start pdftohtml",
		retval => $retval
	})
		if(!$pid);

	# send data
	# XXX: we might need to select for r/w
	binmode($fin);
	syswrite($fin, $data);
	close($fin);

	# read data
	my $buf;
	my $data_out = '';
	while(my $len = sysread($fout, $buf, core::SYS_BUFSIZE)) {	
		$data_out .= $buf; 
	}
	close($fout);
	waitpid($pid, 0);

	my ($doc, $msg) = core::xml::parse($data_out, $url, load_ext_dtd => 0);
	return (undef, {
		msg => $msg 
	})
		if(!$doc);

	# return data
	return ($doc);
}

1;
