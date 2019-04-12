# driver::http::lwp.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package driver::http::lwp;

use strict;
use warnings;

use Encode;
use Data::Dumper;
use XML::LibXML;
use HTTP::Date qw(time2str str2time);
use HTTP::Cookies;
use HTTP::Message;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::http;
use HTTP::Request::Common;

use core::log;

our $MODULE = 'http::lwp';

# FIXME: hack not working ! source has been modified
push(@LWP::Prococol::http::EXTRA_SOCK_OPTS, SendTE => 0);

# cache UA
my $UA;

sub _val($@)
{
	my ($key, @cfg) = @_;
	foreach my $k (@cfg)
	{
		#next if (ref($k) ne 'HASH');
		return $k->{$key}
			if (exists($k->{$key}));
	}
	return undef;
}

sub _prepare_params($@)
{
	my ($key, @confs) = @_;
	my (@params, $k);

	# get param list
	foreach $_ (@confs)
	{
		#next if (ref($k) ne 'HASH');
		push(@params, @{$_->{$key}})
			if (defined($_->{$key}));
	}
	return \@params;
}

sub _request($$$\@\%)
{
	my ($ua, $method, $url, $params, $headers) = @_;

	# transform params
	my @rparams;
	foreach (@$params)
	{
		push(@rparams, $_->{'name'} => (defined($_->{'value'}) ? $_->{'value'} : ''));
#		$rparams{ $_->{'name'} } = defined($_->{'value'}) ? $_->{'value'} : '';
	}

	# fetch now
	my $req;
	if ($method eq 'get')
	{
		$req = $ua->get($url, %$headers);
	}
	elsif ($method eq 'head')
	{
		$req = $ua->head($url, %$headers);
	}
	elsif ($method eq 'post')
	{
		my $hreq = HTTP::Request::Common::POST($url, \@rparams, %$headers);
		$req = $ua->request($hreq);
#die Dumper(\%rparams);
#		$req = $ua->post($url, \%rparams, %$headers);
#die Dumper(\@rparams);
#		$req = $ua->post($url, \@rparams, \%$headers);
	}
	else
	{
		#TODO: croak here
		die('unknown method: ' . $method);
	}
	return $req;
}

sub _redir_handler($$$)
{
    my ($response, $ua, $h) = @_;

    my $request = $response->request();
    my $code = $response->code;

    if ($code == &HTTP::Status::RC_MOVED_PERMANENTLY or
	$code == &HTTP::Status::RC_FOUND or
	$code == &HTTP::Status::RC_SEE_OTHER or
	$code == &HTTP::Status::RC_TEMPORARY_REDIRECT)
    {
	my $referral = $request->clone();

	# These headers should never be forwarded
	$referral->remove_header('Host', 'Cookie');

	if ($referral->header('Referer') &&
	    $request->uri->scheme eq 'https' &&
	    $referral->uri->scheme eq 'http')
	{
	    # RFC 2616, section 15.1.3.
	    # https -> http redirect, suppressing Referer
	    $referral->remove_header('Referer');
	}

	if ($code == &HTTP::Status::RC_SEE_OTHER ||
	    $code == &HTTP::Status::RC_FOUND) 
        {
	    my $method = uc($referral->method);
	    unless ($method eq "GET" || $method eq "HEAD") {
		$referral->method("GET");
		$referral->content("");
		$referral->remove_content_headers();
	    }
	}

	# And then we update the URL based on the Location:-header.
	my $referral_uri = $response->header('Location');
	{
	    # Some servers erroneously return a relative URL for redirects,
	    # so make it absolute if it not already is.
	    local $URI::ABS_ALLOW_RELATIVE_SCHEME = 1;
	    my $base = $response->base;
	    $referral_uri = "" unless defined $referral_uri;
	    $referral_uri = $HTTP::URI_CLASS->new($referral_uri, $base)->abs($base);
	}

	# fix invalid location
	$referral_uri =~ s!^(\w+://[^/]+?)[\?;]!$1/?!o;

	$referral->uri($referral_uri);

	return undef unless $ua->redirect_ok($referral, $response);

	core::log::PKG_MSG(LOG_NOTICE, " redirecting to %s", $referral->uri);
	return $referral;

    }
    elsif ($code == &HTTP::Status::RC_UNAUTHORIZED ||
	     $code == &HTTP::Status::RC_PROXY_AUTHENTICATION_REQUIRED)
    {
    	die(__PACKAGE__ . ": don't know hot process unauthorized redirect !");
    }
    return undef;
}

sub _init($@)
{
	my ($conf, @confs) = @_;

	push(@LWP::Prococol::http::EXTRA_SOCK_OPTS, SendTE => 0);

	my $ua = LWP::UserAgent->new(
		keep_alive => _val('keep_alive', @confs),
		ssl_opts => {
			verify_hostname => 0,
		},
		send_te => 0,
	);
	my $ua_c = HTTP::Cookies->new(file => _val('cookie_file', @confs),
					autosave => defined(_val('cookie_file', @confs)));
	$ua->cookie_jar($ua_c);
	$ua->agent(_val('agent', @confs));
	$ua->max_redirect(_val('redirs', @confs));
	$ua->timeout(_val('timeout', @confs));
	$ua->default_header('Accept' => _val('accept', @confs))
			if (_val('accept', @confs));
	$ua->default_header('Accept-Language' => _val('langs', @confs))
			if (_val('langs', @confs));
	$ua->default_header('Accept-Charset' => $conf->{encoding});
	$ua->default_header('Accept-Encoding' => HTTP::Message::decodable());
	$ua->default_header('DNT' => 1);
	$ua->env_proxy();
	foreach $_ ('http', 'https')
	{
		$ua->proxy($_, _val($_ . '_proxy', @confs))
			if(defined(_val($_ . '_proxy', @confs)));
	}
	$ua->add_handler('response_redirect' => \&_redir_handler);

	return $ua;
}

sub retrieve($$@)
{
	my ($conf, $url, @confs) = @_;
	my $ua;

	# re-use UserAgent
	if (_val('keep_alive', @confs))
	{
		$UA = _init($conf, @confs)
			if (!defined($UA));
		$ua = $UA;
	}
	else
	{
		$ua = _init($conf, @confs);
	}

	# configure redir POST per-request
	@{ $ua->requests_redirectable } = ( 'GET', 'HEAD' );
	push(@{ $ua->requests_redirectable }, 'POST')
		if (_val('redir_post', @confs));

	# extra headers with request
	my (%headers, $get_params, $post_params);
	$get_params	= _prepare_params('get_params', @confs);
	$post_params	= _prepare_params('post_params', @confs);

	# determine method
	my $method = lc(_val('method', @confs) || 'get');
	$method = 'post'
		if (!defined($method)
			&& defined($post_params) && $#$post_params >= 0);

	# build get params
	if (defined($get_params) && @$get_params)
	{
		$url .= '?&'
			if ($url !~ /\?/o);
		foreach $_ (@$get_params)
		{
			$url .= $_->{'name'};
			$url .= (defined($_->{'value'}) ? 
					'=' . $_->{'value'} : '') . '&';
		}

		# cut last '&'
		$url =~ s/&$//o;
	}

	if (core::log::level() > LOG_IMPORTANT)
	{
		my $iurl = $url;
		if (defined($post_params) && @$post_params)
		{
			foreach $_ (@$post_params)
			{
				my $val = defined($_->{'value'}) ? $_->{'value'} : '';
				$iurl .= sprintf(' [%s]=%s', $_->{'name'},
					substr($val, 0, 25) . (length($val) >= 25 ? '...' : ''));
			}
		}
		core::log::PKG_MSG(LOG_NOTICE, " fetching url '%s'", $iurl);
	}

	# fake referer
	$headers{'Referer'} = $url;

	# additional headers
	my $user_headers = _val('headers', @confs);
	%headers = %{ $user_headers }
		if ($user_headers);

	# make request now
	my ($resp, %res);
	$resp = _request($ua, $method, $url, @$post_params, %headers);

	my $ct = $resp->header('Content-Type') || 'text/html';
	$res{'content-type'}	= $ct;
	$res{content}		= $resp->decoded_content;
	$res{content_binary}	= (($resp->content_is_text || $resp->content_is_html
				|| $resp->content_is_xhtml || $resp->content_is_xml
				|| $ct =~ /^application\/(json|javascript)/o) != 1);

	# get result
	$res{code}		= $resp->code;
	$res{status}		= $resp->status_line;
	$res{timestamp}		= str2time($resp->header('Date'));
	$res{expires}		= str2time($resp->header('Expires'));
	$res{server}		= $resp->header('Server');
	$res{uri}		= $resp->base;

	# determine encoding
	# -- supplied by request
	$res{encoding}		= _val('encoding', @confs);
	if (exists($res{content}) && !defined($res{encoding})
		&& ($resp->content_is_html || $resp->content_is_xhtml)
		&& defined($res{'content-type'}) && $res{'content-type'} =~ /\//o)
	{
		# -- from server response
		$res{encoding}		= $1
			if ($res{'content-type'} =~ /;\s*charset=(.+?)\s*$/oi);

		# -- from page
		if ($res{'content-type'} =~ /^text\/html\s*(;|$)/oi
			&& $res{content} =~ /<head>(.*?)<\/head>/sio)
		{
			my $head = $1;

			while($head =~ s/<meta(\s+.*?)\/?>//soi)
			{
				my $meta = $1;

				$res{encoding} = $2
				if ($meta =~ /\s+http-equiv=/oi
					&& $meta =~ /Content-Type/oi
					&& $meta =~ /(\s|\'|\")charset=(.+?)(\s|\'|\")/oi);
			}
		}
	}

	# recode now
	$res{encoding} =~ s/^utf-?8$/utf-8/oi;
	if (defined($res{encoding}) &&
		$res{encoding} ne '' && $res{encoding} ne $conf->{encoding})
	{
		my $cont = decode($res{encoding}, $res{content});
		$res{content} = encode($conf->{encoding}, $cont);
	}

	# clean content type
	$res{'content-type'} = $1
		if ($res{'content-type'} =~ /^(.+?)\s*(;|$)/o && $1 ne '');

	# finito
	return \%res;
}

1;
