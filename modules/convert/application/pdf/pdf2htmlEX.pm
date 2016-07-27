# convert::application::pdf::pdf2htmlEX.pm
#
# Convert pdf to xml via pdf2htmlEX
#
# Copyright: Samuel Behan (c) 2015-2016
#
package convert::application::pdf::pdf2htmlEX;

use strict;
use warnings;

#use Data::Dumper;
use IPC::Open2;

# internal
use core;
use core::log;
use core::xml;
use core::convert;

sub parse($$;$)
{
	my ($data, $url, $reqid) = @_;
#	core::log::SYS_CALL("%s, <DATA>, %s", $reqid, $url || core::NULL_URL);

	# pipe pdftohtml
	my ($fin, $fout);
	my $pid = open2($fout, $fin, "/usr/bin/pdf2htmlEX", "--quiet", "1", "fd://0", "-");
	my $retval = $?;

	return (undef, {
		msg => "failed to start pdf2htmlEX",
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

	# remove javascript
	$data_out =~ s/(<script>.*?<\/script>|\/\*.*?\*\/)//osg;
	$data_out =~ s/<title><\/title>/<title>pdf2htmlEX<\/title>/o;
	$data_out =~ s/<\/div>/&nbsp;<\/div>/og;

	# convert
	if (my $err = core::convert::apply_direct($reqid, $data_out, 'text/html', $url)) {
		return (undef, %$err);
	}

	my ($doc, $msg) = core::xml::parse($data_out, $url);
	if (!$doc || $msg) {
		return (undef, {
			msg => $msg,
		});
	}

	# post-process to make table matching ops easier
	my @nodes = core::findnodes($doc, '//xhtml:div[contains(@class, \' y\')]',
				xhtml => 'http://www.w3.org/1999/xhtml');
	my ($y_node, $y_pos, @y_cols);
	foreach my $node (@nodes) {
		my $class = $node->getAttribute('class');
		next
			if (!$class);

		my @classes = split(/\s+/o, $class);
		my ($x, $y) = sort(grep({ $_ =~ /^[yx]/o } @classes));
		$x = hex(substr($x, 1));
		$y = hex(substr($y, 1));

		$node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':y', $y);
		$node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':x', $x);

		if (!$y_pos || ($y_pos ne $y)) {
		 	if ($y_node) {
				$y_node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':y-col', join(':', @y_cols));
				$y_node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':y-cols', $#y_cols + 1);
			}
			$y_pos = $y;
			$y_node = $node;
			@y_cols = ();
		}
		push(@y_cols, $x);
	}
	if ($y_node) {
		$y_node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':y-col', join(':', @y_cols));
		$y_node->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':y-cols', $#y_cols + 1);
		$doc->documentElement()->setAttributeNS($core::convert::NAMESPACE_URL, $core::convert::MODULE . ':convert-hint', 1);
	}

	# return data
	return $doc;
}

1;
