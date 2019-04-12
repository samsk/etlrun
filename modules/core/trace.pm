# core::trace.pm
#
# Tracing functions
#
# Copyright: Samuel Behan (c) 2015-2016
#
package core::trace;

use strict;
use warnings;

use Exporter;
use Data::Dumper;
use XML::LibXML;

use core::log;

# vars
my $TRACE = 0;
my @TRACE_dirs;
my $TRACE_dir = 0;
my $TRACE_call = 0;
my $TRACE_init = 0;

# cfg
my $XML_DECL = '<?xml version="1.0"?>' . "\n";

# init($directory, [$level])
sub init($;$)
{
	my ($dir, $level) = @_;

	$TRACE = defined($level) ? $level : 1;
	@TRACE_dirs = ($dir);
	$TRACE_dir = $dir;
	$TRACE_call = 0;
	$TRACE_init = 0;
	return;
}

# _init()
sub _init()
{
	# already initialised
	return 1
		if ($TRACE_init);

	# prepare trace dir
	my $path = '';
	my (@path) = split(/\//o, $TRACE_dir);
	if ($path[0] eq '')
	{
		$path = '/';
		shift(@path);
	}
	foreach my $p (@path)
	{
		next if ($p eq '');
		$path .= $p . '/';
		next if (-e $path);

		if (!mkdir($path))
		{
			warn("ERROR: failed to create trace dir '$path' - $!\n");
			return 0;
		}
	}
	$TRACE_init = 1;
	return 1;
}

# _req($level, $reqid, $object [, $ident ])
sub _req($$$;$)
{
	my ($lev, $reqid, $req, $ident) = ($_[0], $_[1], $_[2], $_[3] || 'req');

	# check log level
	return 0 if ($lev > $core::log::LEVEL);

	# not enabled
	return 0 if (!defined($TRACE) || !$TRACE);

	# init tracing
	return 0 if (!_init());

	# log
	core::log::MSG(LOG_DETAIL, "--- trace %s-%04d ---", $reqid, $TRACE_call);

	my $fh;
	my $fn = sprintf("%s/trace-%s-%04d.%s", $TRACE_dir, $reqid, $TRACE_call++, $ident);
	if (!open($fh, '>:utf8', $fn))
	{
		warn("ERROR: failed to create trace file '$fn' - $!\n");
		return 0;
	}

	# write to trace file
	if (ref($req) eq 'XML::LibXML::Document')
	{	$req->toFH($fh, 1);			}
	elsif (ref($req) =~ /^XML::LibXML/o)
	{	print($fh $XML_DECL);
		print($fh $req->toString(1));	}
	elsif (ref($req))
	{	print($fh sprintf("#0x%p\n", $req) . Dumper($req));		}
	else
	{	print($fh $req);			}

	# fini
	close($fh);
	return 1;
}

# req($reqid, $object [, $ident ])
sub req($$;$)
{
	return &_req(LOG_ALWAYS, @_);
}

# req2($level, $reqid, $object [, $ident ])
sub req2($$$;$)
{
	return &_req(@_);
}

sub step($;$)
{
	my ($reqid, $ident) = ($_[0], $_[1] || 'req');

	# not enabled
	return 0 if (!defined($TRACE) || $TRACE < 2);

	# init tracing
	return 0 if (!_init());

	my $dn = sprintf("trace-%s-%04d.%s", $reqid, $TRACE_call++, $ident);
	push(@TRACE_dirs, $dn);
	$TRACE_dir = join('/', @TRACE_dirs);

	if (!mkdir($TRACE_dir))
	{
		warn("ERROR: failed to create trace subdir '$TRACE_dir' - $!\n");
		return 0;
	}
	return 1;
}

sub back($)
{
	my ($reqid) = @_;

	# not enabled
	return 0 if (!defined($TRACE) || $TRACE < 2);

	# init tracing
	return 0 if (!_init());

	pop(@TRACE_dirs);
	$TRACE_dir = join('/', @TRACE_dirs);
	return 1;
}

1;
