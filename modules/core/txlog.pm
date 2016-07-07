# core::txlog.pm
#
# TXLOG manipulation functions
#
# Copyright: Samuel Behan (c) 2014-2016
#
package core::txlog;

use strict;
use warnings;

use core::log;

my ($REQID, $HWM, $LSN) = (0, 1, 1);	# HighWaterMark, $LogSequenceNumber
my ($NAME, $FETCH_FX, $STORE_FX, $LIST_FX);
my ($ENABLED, $INIT) = (1);

# _init()
sub _init
{
	$ENABLED = core::conf::get('txlog.enabled', 0);
	$INIT = 1, return 0
		if (!$ENABLED);

	my $module = 'txlog::' . core::conf::get('txlog.driver', 'fs');
	die(__PACKAGE__ . ": failed to load module '$module'")
		if (!core::auto::load($module));

	# verify config
	$NAME = core::conf::get('txlog.name');
	die(__PACKAGE__ . ": txlog.name must be set if txlog enabled !")
		if (!defined($NAME));

	no strict 'refs';
	my $init = $module . '::init';
	die(__PACKAGE__ . ": failed to init module '$module'")
		if (!&$init());

	# init handlers
	$FETCH_FX = $module . '::fetch';
	$STORE_FX = $module . '::store';
	$LIST_FX = $module . '::list';

	# init config
	$INIT = 1;
	return 1;
}

# new_lsn($reqid): $lsn / undef if disabled
sub newLSN($)
{
	return undef
		if (!$ENABLED);
	_init() || return undef
		if (!$INIT);

	$REQID = $_[0];
	return ++$LSN;
}

# fetch($reqid, $lsn, $req): $resp
sub fetch($$$)
{
	my ($reqid, $lsn, $req) = @_;

	no strict 'refs';
	return &$FETCH_FX($NAME, $reqid, $lsn, $req)
		if (defined($FETCH_FX));

	_init() || return undef;

	# log
	core::log::SYS_CALL(LOG_NOTICE, "%s, %s, %d, <REQ>", $NAME, $reqid, $lsn);
	return &$FETCH_FX($NAME, $reqid, $lsn, $req);
}

# store(reqid, $lsn, $req, $resp): $hwm
sub store($$$$)
{
	my ($reqid, $lsn, $req, $resp) = @_;

	no strict 'refs';
	return ($HWM = &$STORE_FX($NAME, $reqid, $lsn, $req, $resp))
		if (defined($STORE_FX));

	_init() || return undef;

	# log
	core::log::SYS_CALL(LOG_NOTICE, "%s, %s, %d, <REQ>, <RESP>", $NAME, $reqid, $lsn, $req);
	return &$STORE_FX($NAME, $reqid, $lsn, $req, $resp);
}

# list([reqid_pattern]): @txlog_list
sub list($)
{
	my ($reqid) = @_;

	no strict 'refs';
	return ($HWM = &$LIST_FX($NAME, $reqid))
		if (defined($LIST_FX));

	_init() || return undef;

	# log
	core::log::SYS_CALL(LOG_NOTICE, "%s, %s", $NAME, $reqid || '');
	return &$LIST_FX($NAME);
}

1;
