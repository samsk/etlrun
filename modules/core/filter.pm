# core::filter.pm
#
# Universal filtering module.
# Load filter map, mapping filtering condition to specific filter
#	module with additional options.
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::filter;

use strict;
use warnings;

use Data::Dumper;

# internal
use core;
use core::log;
use core::auto;
use core::conf;

my $FILTER_MAP;
my $FILTER_MAP_load = 0;
END { $FILTER_MAP = {}; undef $FILTER_MAP; }

sub _load_filter_map()
{
	my $f = core::conf::file('filter.map');
	my (%map, $type, @ruls, %map2);

	$FILTER_MAP_load = time();
	open(F, $f) || return 0;
	while ((my $l = <F>))
	{
		chomp($l);
		next if ($l =~ /^\#/o || $l =~ /^\s*$/o);

		# find type
		$type = $1, %map2 = (), next
			if ($l =~ /^\[(.+?)\]\s*$/o);
		next if (!defined($type) || !$type);

		my %it;
		my @m = split(/\s+/o, $l);
		if ($m[0] eq '*')
		{
			push(@{ $it{ 'rules' } }, 1);
		}
		else
		{	# prepare (precompile) rules
			my @r = split(/,/o, $m[0]);
			foreach my $r (@r)
			{
				my %it2;
				$r =~ /^(.+?)(=~|!~|!=|=)(.*)$/o;

				my ($k, $op, $rval) = ($1, $2, $3);
				next if (!$op);
				$op = '==' if ($op eq '=');
				$it2{ $k } = { op => $op, rval => $rval };
				if ($op eq '=~' || $op eq '!~')
				{
					$rval =~ s/\\/\\\\/og;
					$it2{ $k }->{ _rval_c } = qr!$rval!;
				}
				push(@{ $it{ 'rules' } }, \%it2);
			}
		}

		# prevent filter instance duplication
		my $map2_key = join('-', @m[1..$#m]);
		if (!exists($map2{ $map2_key }))
		{
			$it{ 'filter' } = $m[1];
			$it{ 'opts' } = splice(@m, 2);

			# add to list
			$type =~ s/\\/\\\\/og;
			$map{ $type }->{ match } = qr!^$type$!i;
			push(@{ $map{ $type }->{ rules } }, \%it);
			$map2{ $map2_key } = $it{ 'rules' };
		}
		else
		{
			push(@{ $map2{ $map2_key } }, @{ $it{ 'rules' } });
		}
	}
	close(F);
	$FILTER_MAP = \%map;
	return 1;
}

sub _eval_expr($$$)
{
	my ($obj, $key, $stack) = @_;

	return 0 if (!defined($obj)
		|| (!exists($stack->{ _rval_c }) && !exists($stack->{ rval })));
	foreach $_ (split(/\./o, $key))
	{
		return 0 if (!defined($obj));
		die if (!ref($obj));
		$obj = $obj->{$_};
	}
	return 0 if (!defined($obj));

	# eval
	my $ret = 0;
	if ($stack->{ op } eq '==' || $stack->{ op } eq '!=')
	{	$ret = "\$ret = (\$obj " . ($stack->{ op } eq '==' ? 'eq' : 'ne') . " '" . $stack->{ rval } . "');";	}
	elsif ($stack->{ op } eq '=~' || $stack->{ op } eq '!~')
	{	$ret = "\$ret = (\$obj " . $stack->{ op } . " /" . $stack->{ _rval_c } . "/);";	}
	$ret = eval $ret;
	return $ret;
}

# _select_filters($type, $obj) : $data
sub _select_filters($$)
{
	my ($type, $obj) = @_;

	# load filter map
	_load_filter_map()
		if (!$FILTER_MAP_load || $FILTER_MAP_load < core::conf::FLAG_RELOAD_TIME());

	# apply filter
	my (@filters);
	foreach $_ (keys(%$FILTER_MAP))
	{
		my $k = $FILTER_MAP->{ $_ };
		next if ($type !~ $k->{ match });

		foreach my $kk (@{ $k->{rules} })
		{
			foreach my $kkk (@{ $kk->{rules} })
			{
				my $res = 1;
				if ($kkk != 1)
				{
					foreach $_ (keys(%$kkk))
					{
						$res = $res && _eval_expr($obj, $_, $kkk->{$_});
						last if (!$res);
					}
				}

				# tests passed - add to list
				push(@filters, $kk)
					if ($res);
			}
		}
		# match only one type
		last;
	}
	return @filters;
}

# apply_direct($reqid, $data, $content_type, $url)
sub apply_direct($\$$$)
{
	my ($reqid, $data, $ct, $url) = @_;

	core::log::SYS_CALL("%s, %s, <DATA>, %s", $reqid, $ct, $url || core::NULL_URL);

	# nothing to do here ?
	return undef
		if (!$url);
	core::log::PKG_MSG(LOG_INFO, " - url: %s", $url || core::NULL_URL);

	# build filter match object
	my $obj_url = core::url::parse($url);
	my $obj = {
		url => $obj_url,
	};

	# select filters now
	my @filters = _select_filters($ct, $obj);
	return undef
		if (!@filters);

	# apply now
	my $data_changed = 0;
	foreach my $filter (@filters)
	{
		core::log::PKG_MSG(LOG_INFO, " - applying filter '%s'", $filter->{ filter });

		my $fn = $filter->{ filter };
		if (!core::auto::load($fn))
		{
			my ($resp, $nod) = core::create_response($reqid, __PACKAGE__);
			$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				data => $$data,
				msg => 'BAD FILTER: filter driver could not be loaded',
				filter => $fn));
			return $resp;
		}

		# process now
		local $@;

		$fn .= '::apply';
		my $changed = eval { no strict 'refs'; &$fn($reqid, $ct, $data, $filter->{ opts }); };
		if (!defined($changed))
		{
			my ($resp, $nod) = core::create_response($reqid, __PACKAGE__);
			$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				error => $@,
				msg => 'BAD FILTER: driver returned undefined response',
				filter => $fn));
			return $resp;
		}
		$data_changed += $changed;
	}

	core::log::PKG_MSG(LOG_NOTICE, " - %d changes made", $data_changed);
	return undef;
}

1;
