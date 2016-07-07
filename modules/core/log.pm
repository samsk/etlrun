# core::log.pm
#
# Logging functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::log;

use strict;
use warnings;

use Exporter;
use Data::Dumper;
use XML::LibXML;
use Scalar::Util qw(looks_like_number);

# export
our @ISA = qw(Exporter);
our @EXPORT = qw(LOG_ALWAYS LOG_FATAL LOG_IMPORTANT LOG_WARNING LOG_NOTICE LOG_INFO LOG_DETAIL);

# constants
use constant _LOG_BASE_MUL	=> 1;
use constant LOG_ALWAYS		=> 0;
use constant LOG_FATAL		=> 0;
use constant LOG_IMPORTANT	=> 1;
use constant LOG_WARNING	=> 2;
use constant LOG_NOTICE		=> 3;
use constant LOG_INFO		=> 4;
use constant LOG_DETAIL		=> 5;
use constant LOG_DEFAULT	=> LOG_ALWAYS;

use constant _LOG_MUL		=> 10;
use constant LOG_MSG		=> _LOG_MUL * 1; # MESSAGE
use constant LOG_PKG_MSG	=> _LOG_MUL * 2; # MESSAGE from PKG
use constant LOG_SUB_MSG	=> _LOG_MUL * 3; # MESSAGE from SUB

# SYS
use constant _LOG_SYS_MUL	=> 100;
use constant LOG_SYS_RESOURCE	=> _LOG_SYS_MUL * 1; # RESOURCE usage
use constant LOG_SYS_REQUEST	=> _LOG_SYS_MUL * 2; # REQUEST processing
use constant LOG_SYS_CALL	=> _LOG_SYS_MUL * 3; # DRIVER call

# USER
use constant _LOG_USER_MUL	=> 10000;
use constant LOG_USER		=> _LOG_USER_MUL * 1; # USER msg
use constant LOG_USER1		=> _LOG_USER_MUL * 2; # 
use constant LOG_USER2		=> _LOG_USER_MUL * 3; #

# DEBUG
use constant _LOG_DEBUG_MUL	=> 100000;
use constant LOG_DEBUG		=> _LOG_DEBUG_MUL * 1; # DEBUG msg
use constant LOG_DEBUG1		=> _LOG_DEBUG_MUL * 2; #
use constant LOG_DEBUG2		=> _LOG_DEBUG_MUL * 3; #

use constant LOG_OPT_REQID	=> 1000000;
use constant LOG_OPT_BACKTRACE	=> 2000000;

# vars
our $LEVEL = LOG_DEFAULT;
our $LEVEL_USER = LOG_DEFAULT;
my $REQID;

# level([ $level ])
sub level(;$)
{
	$LEVEL = $_[0] if (defined($_[0]));
	return $LEVEL;
}

# level_user([ $level ])
sub level_user(;$)
{
	$LEVEL_USER = $_[0] if (defined($_[0]));
	return $LEVEL_USER;
}

sub reqid(;$)
{
	$REQID = $_[0] if (defined($_[0]));
	return $REQID;
}

# log($level, $format, ...)
sub _log($$@)
{
	my ($type, $lev, $msg) = (shift, shift, shift);
	my $is_user = int(int($type / _LOG_USER_MUL) % 10);

	return 0
		if ((!$is_user && $lev > $LEVEL) || ($is_user && $lev > $LEVEL_USER));

	chomp($msg);
	return printf(STDERR $msg . "\n", @_);
}

# _log2($frames, $level, $format, ...)
sub _log2($$$@)
{
	my ($frames, $type, $lev, $msg) = (shift, shift, shift, shift);

	my (undef, undef, undef, $sub) = caller($frames || 1);
	return __PACKAGE__::log($lev, $sub . ($msg ? $msg : ""), @_);
}

# _log3($prefix, $postfix, $type, [$level, ] $format, ...)
sub _log3($$$@)
{
	my ($prefix, $postfix, $type) = (shift, shift, shift);

	my $lev = $_[0];
	if (looks_like_number($lev)) {
		$lev = shift;
	} else {
		$lev = LOG_DEFAULT;
	}

	my $fmt = shift;
	$fmt = (defined($prefix)) ? $prefix . $fmt : $fmt;
	$fmt = (defined($postfix)) ? $fmt . $postfix : $fmt;

	return _log($type, $lev, $fmt, @_);
}

# _log4($prefix, $postfix, $type, $deflevel, [$level, ] $format, ...)
sub _log4($$$@)
{
	my ($prefix, $postfix, $type, $deflevel) = (shift, shift, shift, shift);

	my $lev = $_[0];
	if (looks_like_number($lev)) {
		$lev = shift;
	} else {
		$lev = $deflevel;
	}

	my $fmt = shift;
	$fmt = (defined($prefix)) ? $prefix . $fmt : $fmt;
	$fmt = (defined($postfix)) ? $fmt . $postfix : $fmt;

	return _log($type, $lev, $fmt, @_);
}


# MSG([$level, ] $format, ...)
sub MSG($@)
{
	return _log3(undef, undef, LOG_MSG, @_);
}

# PKG_MSG([$level, ] $format, ...)
sub PKG_MSG($@)
{
	my ($package) = caller(0);
	return _log3($package, undef, LOG_PKG_MSG, @_);
}


# SUB_MSG([$level, ] $format, ...)
sub SUB_MSG($@)
{
	my (undef, undef, undef, $sub) = caller(1);
	return _log3($sub, undef, LOG_SUB_MSG, @_);
}

# SYS_RESOURCE([$level, ] $format, ...)
sub SYS_RESOURCE($@)
{	
	my ($package) = caller(0);
	return _log4($package, undef, LOG_SYS_RESOURCE, LOG_IMPORTANT, @_);
}

# SYS_REQUEST([$level, ] $format, ...)
sub SYS_REQUEST($@)
{
	return _log4(undef, undef, LOG_SYS_REQUEST, LOG_DETAIL, @_);
}

# SYS_CALL([$level, ] $format, ...)
sub SYS_CALL($@)
{
	my (undef, undef, undef, $sub) = caller(1);
	return _log4($sub . '(', ')', LOG_SYS_CALL, LOG_DETAIL, @_);
}

# USER([$level, ] $format, ...)
sub USER($@)
{
	return _log3(undef, undef, LOG_USER, @_);
}

# USER1([$level, ] $format, ...)
sub USER1($@)
{
	return _log3(undef, undef, LOG_USER1, @_);
}

# USER2([$level, ] $format, ...)
sub USER2($@)
{
	return _log3(undef, undef, LOG_USER2, @_);
}

# DEBUG([$level, ] $format, ...)
sub DEBUG($@)
{
	return _log3(undef, undef, LOG_DEBUG, @_);
}

# DEBUG1([$level, ] $format, ...)
sub DEBUG1($@)
{
	return _log3(undef, undef, LOG_DEBUG1, @_);
}

# DEBUG2([$level, ] $format, ...)
sub DEBUG2($@)
{
	return _log3(undef, undef, LOG_DEBUG2, @_);
}

# dump($level, $msg, $var [, $depth])
sub dump($$$;$)
{
	my ($lev, $msg, $var, $depth) = @_;
	my $str;

	return 0
		if ($lev > $LEVEL);

	if ($var && substr(ref($var), 0, 11) eq 'XML::LibXML') {
		$str = $var->toString(1);
	} else {
		$Data::Dumper::Maxdepth = ($depth || 0);
		$str = Dumper($var);
		$Data::Dumper::Maxdepth = 0;
	}

	return print(STDERR " --- BEGIN DUMP $msg ---\n", $str, "\n --- END DUMP $msg ---\n");
}

# warn($level, $message [, $retval ]): retval
sub warning($$;$)
{
	my ($lev, $msg, $ret) = @_;

	warn("WARNING: [$lev] $msg\n");
	return $ret;
}

# error($level, $message [, $retval ]): retval
sub error($$;$)
{
	my ($lev, $msg, $ret) = @_;

	warn("ERROR: [$lev] $msg\n");
	return $ret;
}

1;
