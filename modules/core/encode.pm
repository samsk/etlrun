# core::encode.pm
#
# encoding functions
#
# Copyright: Samuel Behan (c) 2013-2016
#
package core::encode;

use strict;
use warnings;

#use Data::Dumper;
use MIME::Base64 qw( );

# base64_encode($data): $data
sub base64_encode($)
{
	return MIME::Base64::encode($_[0]);
}

# base64_decode($data): $data
sub base64_decode($)
{
	return MIME::Base64::decode($_[0]);
}

1;
