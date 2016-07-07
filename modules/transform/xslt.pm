# transform::xslt.pm
#
#
# Copyright: Samuel Behan (c) 2011-2016
#
package transform::xslt;

use strict;
use warnings;

use Data::Dumper;
use XML::LibXSLT;
use XML::LibXML;
use Digest::SHA qw(sha1_hex);

# internal
use core;
use core::log;
use core::lru;
use core::conf;
use core::xml;
use core::kernel;

# cache
my $XSLT;
my $CACHE;
END { undef $XSLT; undef $CACHE; }

sub apply($$$$$%)
{
	my ($reqid, $req_doc, $doc, $xslt, $params, %params) = @_;
	core::log::SYS_CALL("%s, 0x%p, <DATA>, %s, <PARAMS>", $reqid, $req_doc, $xslt);

	# lru cache
	my $sheet;
	my $sheet_cache = core::lru::get($CACHE, $xslt);
	if (!defined($sheet_cache) || !exists($sheet_cache->{'sheet'})
		|| $sheet_cache->{-ctime} < core::conf::FLAG_RELOAD_TIME())
	{
		# get source
		my $src = core::kernel::process($reqid, $req_doc, $xslt, %params);
		die("failed to fetch $xslt")
			if (!defined($src));

		# test for error
		return $src
			if (core::get_error($src));

		# get data
		my $src_xsl = $src->documentElement()->firstChild();
		if (!defined($src_xsl))
		{
			my $doc = core::xml::create_document();
			$doc->setDocumentElement(core::raise_error($reqid, __PACKAGE__, 500,
				source => $xslt,
				xml => $src_xsl,
				msg => 'XSLT stylesheet is empty'));
			return $doc;
		}

		my $xsl_doc = core::xml::create_document();
		$xsl_doc->setDocumentElement($xsl_doc->importNode($src_xsl));

		$sheet = eval { $XSLT->parse_stylesheet($xsl_doc); };
		if (!defined($sheet))
		{
			my $doc = core::xml::create_document();
			$doc->setDocumentElement(core::raise_error($reqid, __PACKAGE__, 500,
				source => $xslt,
				msg => 'failed to parse XSLT stylesheet',
				detail => $@));
			return $doc;
		}

		# cache it
		$sheet_cache = { 'sheet' => $sheet, -ctime => time() };
		core::lru::set($CACHE, $xslt, $sheet_cache, core::conf::get('transform.xslt.lru-size', 30));
	}
	else
	{	$sheet = $sheet_cache->{'sheet'};	}

	# transform params
	my $pars = {};
	_trans_params($params, $pars);

	# transform
#	$doc->indexElements()
#		if (ref($doc) eq 'XML::LibXML::Document');
	my $resp = eval { $sheet->transform($doc, %$pars); };
	if (!defined($resp))
	{
		my $doc = core::xml::create_document();

		# strip croak line
		$@ =~ s/\.\n( at.+?)\d+\n/./o;
		$doc->setDocumentElement(core::raise_error($reqid, __PACKAGE__, 500,
			req => $xslt,
			msg => 'XSLT transformation failed',
			detail => $@));
		return $doc;
	}

	return $resp;
}

sub init($)
{
	my ($function_map) = @_;

	# already initialised
	return $XSLT
		if (defined($XSLT));

	# create transformer
	$XSLT = new XML::LibXSLT();
	$XSLT->max_depth(99);

=cut
	# add security restrict
	my $security = XML::LibXSLT::Security->new();

	$security->register_callback( read_file  => $read_cb );
	$security->register_callback( write_file => $write_cb );
	$security->register_callback( create_dir => $create_cb );
	$security->register_callback( read_net   => $read_net_cb );
	$security->register_callback( write_net  => $write_net_cb );

	$XSLT->security_callbacks( $security );
=cut

	# map functions
	foreach my $it (@$function_map)
	{
		my $ns = $it->{'ns'};
		my $name = $it->{'name'};
		my $handle = $it->{'handle'};

		# register function now
		$XSLT->register_function($ns, $name, $handle);
	}

	return $XSLT;
}

sub _xslt_value($)
{
	my ($value) = $_[0];

	return "''"
		if (!defined($value));
	return $value
		if ($value =~ /^[[:digit:]]+$/o);
	return "'" . $value . "'";
}

# map complex structure to simple hash
sub _trans_params($\$;$)
{
	my ($params, $pars, $prefix) = @_;

	if (ref($params) eq '')
	{
		$pars->{ $prefix } = _xslt_value($params);
		return;
	}

	if (defined($prefix) && $prefix ne '')
	{	$prefix .= '_';	}
	else
	{	$prefix = '';	}

	foreach my $pk (keys %$params)
	{
		next
			if ($pk !~ /^\w+$/o);

		if (ref($params->{$pk}) eq 'HASH')
		{
			&_trans_params($params->{$pk}, $pars, $prefix . $pk);
		}
		elsif (ref($params->{$pk}) eq 'ARRAY')
		{
			for (my $ia = 0; $ia <= $#{$params->{$pk}}; $ia++)
			{
				&_trans_params($params->{$pk}[$ia], $pars, $pk . '_' . $ia);
			}
		}
		elsif (ref($params->{$pk}) eq '')
		{
			$pars->{ $prefix . $pk } = _xslt_value($params->{$pk});
		}
	}
}

1;
