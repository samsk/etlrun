# core::convert.pm
#
# Universal conversion module.
# Load filter map, mapping filtering condition to specific filter
#	module with additional options.
#
# Copyright: Samuel Behan (c) 2012-2016
#
package core::convert;

use strict;
use warnings;

use Data::Dumper;

# internal
use core::log;
use core::auto;
use core::conf;
use core::filter;

# apply_direct($reqid, $data, $content_type, $url)
sub apply_direct($\$$$)
{
	my ($reqid, $data, $ct, $url) = @_;
	core::log::SYS_CALL("%s, %s, <DATA>, %s", $reqid, $ct, $url || core::NULL_URL);

	# convert bad content type
	my $convert_driver;
	while (defined($ct) && $ct ne core::CT_OK)
	{
		# trace convert
		core::trace::req2(LOG_INFO, $reqid, $$data, 'filter');

		# clean by filters if needed
		if (my $err_resp = core::filter::apply_direct($reqid, $$data, $ct, $url)) {
			return $err_resp;
		}

		# trace convert
		core::trace::req2(LOG_DETAIL, $reqid, $$data, 'filter-out');

		# try default match
		$convert_driver = lc($ct);
		$convert_driver =~ s/\//::/og;
		$convert_driver = 'convert::' . $convert_driver;
		if (!core::auto::load($convert_driver))
		{
			#FIXME: try to use mapping file here
			$ct = undef;
			next;
		}
		my $fn = $convert_driver . '::from';

		# trace convert
		core::trace::req2(LOG_NOTICE, $reqid, $$data, 'convert:' . $convert_driver);

		# go
		my $err;
		local $@;

		core::log::SUB_MSG(LOG_NOTICE, " - call %s(%s, <DATA>, %s)", $fn, $reqid, $url || core::NULL_URL);
		($err, $ct) = eval { no strict 'refs'; &$fn($reqid, $data, $url); };
		if (!defined($err) || !defined($ct))
		{
			return {
				_code => 502,
				error => $@,
				msg => 'BAD CONVERTOR: convertor returned undefined response',
				driver => $convert_driver };
		}
		elsif ($ct eq core::CT_ERROR)
		{
			return {
				_code => 500,
				msg => 'CONVERTOR FAIL: unknown error',
				%$err,
				driver => $convert_driver };
		}

		# trace convert out
		core::trace::req2(LOG_INFO, $reqid, $$data, 'convert-out:' . $convert_driver);
	}
	return undef;
}

# apply($reqid, $resp, $content_type): mixed
sub apply($$$)
{
	my ($reqid, $resp, $ct) = @_;

	return $resp if (!$ct);
	core::log::SYS_CALL("%s, %s, %s",
			$reqid,
			(ref($resp) ?  "<DATA>" : "'" . substr($resp || "", 0, 23) . "'"),
			$ct || '_UNKNOWN_');

	my ($data) = core::get_data($resp);
	return $resp
		if (!$data || core::xml::getFirstElementChild($data));

	# need convert ?
	return $resp
		if (core::xml::getFirstElementChild($data));

	# get content
	my $ct_ori = $ct;
	my $cont = core::get_data_content($resp, $data);

	# findout document url
	my ($url, $node);
	$url = core::get_uri($node)
		if ($node = core::get_data_root($data));
	$url = core::get_uri($node)
		if (!$url && ($node = core::get_data($data)));
	$url = core::get_uri($resp)
		if (!$url);

	# apply now
	if (my $err = apply_direct($reqid, $cont, $ct, $url))
	{
		my ($doc, $nod) = core::create_response($reqid, __PACKAGE__);
		$nod->appendChild(core::raise_error($reqid, __PACKAGE__,
			(ref($err) eq 'HASH' && exists($err->{'_code'}) ? $err->{'_code'} : 500),
			exterr => $err,
			url => $url,
			req => $resp,
			_fatal => $doc));
		return $doc;
	}

	# replace original data
	core::replace_data_content($data, $cont);
	core::set_attrib($data, core::ATTR_CONTENT_TYPE_ORI, $ct_ori);
	core::set_attrib($data, core::ATTR_CONTENT_TYPE, $ct);
	return $resp;
}

# pluginize($package, $plugin, $dataptr, $url [, $reqid]) : ($converted, @result)
sub pluginize($$$$;$)
{
	my ($package, $plugin, $dataptr, $url, $reqid) = @_;

	local $@;
	my ($out, $err);
	if (!core::auto::load($package . '::' . $plugin)) {
		return ({ msg => "failed to load plugin '$plugin'" }, core::CT_ERROR);
	}
	else
	{
		my $fn = sprintf($package . '::%s::parse', $plugin);
		core::log::SUB_MSG(LOG_NOTICE, " - call %s(<DATA>, %s)", $fn, $url || '???');

		($out, $err) = eval {
			no strict 'refs';
			&$fn($$dataptr, $url, $reqid);
		};
	}

	# handle error
	if (!defined($out) || (defined($err) && ref($err))) {
		$err = { msg => $@,
				plugin => $plugin }
			if (!defined($err));

		return (0, { out => $out,
				plugin => $plugin,
				%$err }, core::CT_ERROR);
	# need reconvert
	} elsif (defined($err)) {
		$$dataptr = $out;
		return (0, $$dataptr, $err);
	}

	# ok
	return (1, $out);
}

1;
