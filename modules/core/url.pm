# core::url.pm
#
# URL functions
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::url;

use strict;
use warnings;

#use Data::Dumper;

our $CLASS = 'url';

# parse($string): $url_class
sub parse($)
{
	my ($url) = @_;
	my ($loc, $schema, $user, $pass, $host, $port, $path, $pkg, $param, $query, $fragment);

	# replace xml entities
	$url =~ s/&amp;/&/og;
	$url =~ s/&gt;/>/og;
	$url =~ s/&lt;/</og;

	# check params
	die(__PACKAGE__ . '::parse($url, $resp): ' . $url . ' - incorect url format - should be <schema>://<location> !')
		if ($url!~ /^([\w+]+):\/\/(([^:@]+)(:([^@]+))?@)?(([^:\/]+)(:([^\/]+))?)?((\/[^;\?\#]*)(;([^\?\#]*))?(\?([^\#]*))?(#(.*))?)?$/o);
	$schema =$1;
	$user = $3;
	$pass = $5;
	$host = defined($7) ? $7 : '';
	$port = $9;
	$path = defined($11) ? $11 : '';
	$param = $13;
	$query = $15;
	$fragment = $17;
	$loc = (defined($2) ? $2 : '') . (defined($6) ? $6 : ''). $path;

	# build url parts
	my $resp 		= {};
	$resp->{href}		= $url;
	$resp->{loc}		= $loc;
	$resp->{schema}		= $schema;
	$resp->{user}		= $user;
	$resp->{password}	= $pass;
	$resp->{host}		= $host;
	$resp->{port}		= $port;
	$resp->{path}		= $path;
	$resp->{param}		= $param;
	$resp->{query}		= $query;
	$resp->{fragment}	= $fragment;
	$resp->{pkg}		= join('.', reverse(split(/\./o, $host)))
		if ($schema ne 'file');

	bless($resp, $CLASS);
	return $resp;
}

1;
