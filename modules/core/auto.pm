# core::auto.pm
#
# Automatical module loading
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::auto;

use strict;
use warnings;

#use Data::Dumper;

# list of loaded mods
our %LOADED;
END { %LOADED = (); undef %LOADED; }

# module extension
my $mod_ext = '.pm';

sub _load_dir($$)
{
	my ($dir, $mpath) = @_;
	my $ret = 1;

	return 0 if (!opendir(D, $dir));
	while (defined(my $fn = readdir(D)) && $ret)
	{
		next if ($fn eq '.' || $fn eq '..'
			|| $fn !~ /^(.+?)$mod_ext$/o);
		my $fn2 = $dir . '/' . $fn;
		my $fn3 = $mpath . '/' . $fn;
		next if (! -f $fn2 || exists($INC{ $fn3 })
			|| (exists($LOADED{ $fn3 }) && $LOADED{ $fn3 }));
		require $fn3;
		$LOADED{ $fn3 } = $ret = (exists($INC{$fn3}) && defined($INC{$fn3})) ? 1 : 0;
	}
	closedir(D);
	return $ret;
}

sub load($)
{
	my $path = shift;
	my $mpath = $path;

	# rewrite to path
	$mpath =~ s!::\*?$!!o;
	$mpath =~ s!::!/!og;

	# already loaded
	return 1 if (exists($LOADED{$mpath}) && $LOADED{$mpath});

	# traverse INC
	my $ret = 0;
	foreach my $dn (@INC)
	{
		if (-d $dn . '/' . $mpath && $path =~ /::\*?$/o)
		{
			$ret = _load_dir($dn . '/' . $mpath, $mpath);
			last;
		}
		if (-e $dn . '/' . $mpath . $mod_ext)
		{
			require $mpath . $mod_ext
				if (!exists($INC{ $mpath . $mod_ext }));
			$ret = (exists($INC{ $mpath . $mod_ext })
					&& defined($INC{ $mpath . $mod_ext })) ? 1 : 0;
			last;
		}
	}
	$LOADED{$mpath}	= $ret;
	return $ret;
}

1;
