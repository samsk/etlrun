# core::transform.pm
#
# Document abstraction functions + native functions for XML handling
#
# Copyright: Samuel Behan (c) 2011-2016
#
package core::transform;

use strict;
use warnings;

use Encode;
use Data::Dumper;
use Scalar::Util;
use Text::Unidecode;
#use Unicode::Normalize;

# internal
use core;
use core::log;
use core::conf;
use core::auto;

my %INIT_MAP;
my (@FUNCTION_MAP, @FUNCTION_MAP_def);
my $FUNCTION_MAP_load = 0;
END { %INIT_MAP = (); undef %INIT_MAP;
	@FUNCTION_MAP = (); undef @FUNCTION_MAP; }

sub _load_function_map()
{
	my $f = core::conf::file('function.map') || return 0;
	my $type = core::NAMESPACE_URL;

	$FUNCTION_MAP_load = time();
	open(F, $f) || return 0;

	my @list;
	while ((my $l = <F>))
	{
		chomp($l);
		next if ($l =~ /^\#/o || $l =~ /^\s*$/o);

		# find type
		$type = $1, next
			if ($l =~ /^\[(.+?)\]\s*$/o);
		next if (!defined($type) || !$type);

		# default namespace mapping
		$type = core::NAMESPACE_URL
			if ($type eq '$CORE$');

		# list
		my ($name, $funct, @opts) = split(/\s+/o, $l);

		# check input
		next if (!$name || !$funct);
		core::log::SUB_MSG(LOG_FATAL, "  - function %s not in user:: namespace", $funct), next
			if ($funct !~ /^user::/o);

		# parse
		next if ($funct !~ /^((\w+|::)*?)::(\w+)$/o);
		my ($module, $sub) = ($1, $3);

		# load module
		core::log::SUB_MSG(LOG_FATAL, " - failed to load module %s", $module), next
			if (!core::auto::load($module));

		# eval function
		no strict 'refs';

		my $handle = eval { \&$funct };
		core::log::SUB_MSG(LOG_FATAL, " - failed to resolve function %s", $funct), next
			if (!$handle);

		# load
		push(@list, {
			ns => $type,
			name => $name,
			function => $funct,
			handle => $handle,
			opts => \@opts });
	}
	close(F);
	push(@FUNCTION_MAP, @list);
	return 1;
}

# apply($reqid, $req_doc, $doc, $url, %tparams, %params)
sub apply($$$$\%%)
{
	my ($reqid, $req_doc, $doc, $url, $params, %params) = @_;

	# parse req
	if ($url !~ /^(\w+):(.*?)$/o)
	{
		my ($resp, $nod) = core::create_response($reqid, __PACKAGE__);
		$nod->addChild(core::raise_error($reqid, __PACKAGE__, 400,
			_fatal => $resp,
			req => $url,
			params => $params,
			msg => 'BAD REQUEST: transformation driver not specified'));
		return $resp;
	}

	my $driver;
	($driver, $url) = ($1, $2 || '');

	# init if needed
	if (!exists($INIT_MAP{$driver}) || $INIT_MAP{$driver} < core::conf::FLAG_RELOAD_TIME())
	{
		if (!core::auto::load("transform::$driver"))
		{
			my ($resp, $nod) = core::create_response($reqid, __PACKAGE__);
			$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				req => $url,
				params => $params,
				msg => 'BAD DRIVER: transform driver could not be loaded',
				driver => "transform::$driver"));
			$INIT_MAP{$driver} = 0;
			return $resp;
		}

		# load filter map
		_load_function_map()
			if (!$FUNCTION_MAP_load || $FUNCTION_MAP_load < core::conf::FLAG_RELOAD_TIME());

		no strict 'refs';
		my $fn = "transform::${driver}::init";
		if (!&$fn(\@FUNCTION_MAP))
		{
			my ($resp, $nod) = core::create_response($reqid, __PACKAGE__);
			$nod->addChild(core::raise_error($reqid, __PACKAGE__, 502,
				_fatal => $resp,
				req => $url,
				params => $params,
				msg => 'BAD DRIVER: transform driver could not be initialized',
				driver => "transform::$driver"));
			$INIT_MAP{$driver} = 0;
			return $resp;
		}

		# mark load time
		$INIT_MAP{$driver} = time();
	}

	# trace
	core::trace::req($reqid, $url, 'transform-url');
	core::trace::req($reqid, $doc, 'transform-doc');

	# document uri
	my $uri = $doc->ownerDocument()->URI();

	# apply
	no strict 'refs';
	my $fn = "transform::${driver}::apply";
	my $res = &$fn($reqid, $req_doc, $doc, $url, $params, %params);

	# add uri to result
	$res->ownerDocument()->setURI($uri)
		if ($uri);

	# trace
	core::trace::req($reqid, $res, 'transform-res');
	return $res;
}

###
# DEFAULT BUILTINS
### 

# parse string to xml, and return it
sub _xsl_str2xml($)
{
	my ($str) = @_;

	my $doc;
	eval {
#		$SIG{__WARN__} = undef;
		$doc = core::xml::parse('<r>' . $str . '</r>');
	};
	return ($doc ? $doc->findnodes("/r/*") : undef);
}

# convert xml to string, and return it
sub _xsl_xml2str($)
{
	my ($xml) = @_;

	return undef
		if (!defined($xml));
	return $xml
		if (!ref($xml));

	my $ret = '';
	foreach my $n ($xml->get_nodelist()) {	
		$ret .= $n->toString(1) . "\n";
	}
	return $ret;
}

sub __xsl_regex_compile($)
{
	my ($m) = @_;

	local $2;
	my $x = eval { qr/$m/; };

	return ($x, ($@ ? "REGEX[$m]: $@" : undef));
}

# regex_match
sub _xsl_regex_match($$)
{
	my ($str, $m) = @_;
	
	my ($x, $e) = __xsl_regex_compile($m);
	return $e
		if ($e);

	return ($str =~ /$x/);
}

# regex_match_substr
sub _xsl_regex_match_substr($$$)
{
	my ($str, $m, $p) = @_;

	my ($x, $e) = __xsl_regex_compile($m);
	return $e
		if ($e);

	$p = 1
		if (!$p || !Scalar::Util::looks_like_number($p) || $p < 1);

	my @ret = ( $str =~ m/$x/g );
	return $ret[$p - 1];
}


# regex_replace
sub _xsl_regex_replace($$$;$)
{
	my ($str, $m, $r, $a) = @_;

	my ($x, $e) = __xsl_regex_compile($m);
	return $e
		if ($e);
	
	if (!defined($r)) {
		$r = '\'\'';
	} else {
		my $rr = '\'';

		# safe eval
		my @arr = split(/\$/o, $r);
		for(my $ii = 0; $ii <= $#arr; $ii++) {
			if ($arr[$ii] =~ s/^(([[:digit:]]{1,2})|{([[:digit:]]{1,2})})//o) {
				$rr .= '\' . "$' . $1 . '" . \'';
			}
			$rr .= $arr[$ii];
		}

		$rr .= '\'';
		$r = $rr;
	}

	if ($a) {
		no warnings;
		$str =~ s/$x/$r/eeg;
	} else {
		no warnings;
		$str =~ s/$x/$r/ee;
	}
	return $str;
}

# regex_replace_all
sub _xsl_regex_replace_all($$$)
{
	$_[3] = 1;
	return &_xsl_regex_replace(@_);
}

# regex_split
sub _xsl_regex_split($$;$)
{
	my ($str, $m, $l) = @_;

	my ($x, $e) = __xsl_regex_compile($m);
	return $e
		if ($e);

	$l = 0
		if (!$l || !Scalar::Util::looks_like_number($l));

	my @nodes = map({ XML::LibXML::Text->new( $_ ) } split($x, $str, $l));
	return XML::LibXML::NodeList->new(@nodes);
}

# seq
sub _xsl_seq($;$$)
{
	my ($first, $inc, $last) = (1, 1, 0);

	# get params
	if ($#_ == 2)
	{	($first, $inc, $last) = @_;	}
	elsif ($#_ == 1)
	{	($first, $last) = @_;		}
	elsif ($#_ == 0)
	{	($last) = @_;			}

	# sanity
	$inc = 1 if (!$inc);

	# un-object it
	foreach (\$first, \$inc, \$last)
	{
		$$_ = $$_->string_value()
			if (ref($$_));
	}

	# create nodes
	my @nodes;
	for (; $first <= $last; $first += $inc) {
		push(@nodes, XML::LibXML::Text->new( $first ));
	}
	return XML::LibXML::NodeList->new(@nodes);
}

# env
sub _xsl_env($)
{
	return $ENV{ $_[0] };
}

# ifnull
sub _xsl_ifnull(@)
{
	foreach my $obj (@_)
	{
		return $obj
			if ($obj && ((ref($obj) && $obj->size() != 0)
				|| $obj));
	}
	return '';
}

# if
sub _xsl_if($$$)
{
	my ($test, $obj1, $obj2) = @_;

	return ($test) ? $obj1 : $obj2
		if (!$test || !ref($test));
	return ($test->size() != 0 ? $obj1 : $obj2);
}

# sleep
sub _xsl_sleep($)
{
	my ($secs) = @_;

	sleep($secs || 1);
	return 0;
}

# getenv
sub _xsl_getenv($;$)
{
	my ($var, $def) = @_;

	return (exists($ENV{$var}) && defined($ENV{$var})) ? $ENV{$var} : ($def || '');
}

# lc
sub _xsl_lc($)
{
	my ($str) = @_;

	return lc($str);
}

# uc
sub _xsl_uc($)
{
	my ($str) = @_;

	return uc($str);
}

# _xsl_trim
sub _xsl_trim($)
{
	my ($str) = @_;

	$str =~ s/(^\s+|\s+$)//og;
	return $str;
}

# _xsl_unaccent
sub _xsl_unaccent($)
{
	my ($str) = @_;

#	$str = NFKD($str);
#	$str =~ s/\p{NonspacingMark}//og;
#	return $str;
	return unidecode($str);
}

# add default functions
@FUNCTION_MAP_def = (
	## FUNCTION etl:str2xml($string): $node-set
	{ ns => core::NAMESPACE_URL,	name => 'str2xml',	handle => \&_xsl_str2xml },
	## FUNCTION etl:xml2str($node-set): $string
	{ ns => core::NAMESPACE_URL,	name => 'xml2str',	handle =>\&_xsl_xml2str },
	## FUNCTION etl:regex-match($string, $match): $string
	{ ns => core::NAMESPACE_URL,	name =>'regex-match', handle => \&_xsl_regex_match },
	## FUNCTION etl:regex-match-substr($string, $position, $match): $string
	{ ns => core::NAMESPACE_URL,	name =>'regex-match-substr', handle => \&_xsl_regex_match_substr },
	## FUNCTION etl:regex-replace($string, $match, $replace, $all): $string
	{ ns => core::NAMESPACE_URL,	name =>'regex-replace', handle => \&_xsl_regex_replace },
	## FUNCTION etl:regex-replace-all($string, $match, $replace): $string
	{ ns => core::NAMESPACE_URL,	name =>'regex-replace-all', handle => \&_xsl_regex_replace_all },
	## FUNCTION etl:regex-split($string, $match, $limit): $node-set
	{ ns => core::NAMESPACE_URL,	name =>'regex-split', handle => \&_xsl_regex_split },
	## FUNCTION etl:seq($first [ [ ,$inc ], $last): $node-set
	{ ns => core::NAMESPACE_URL,	name => 'seq',		handle => \&_xsl_seq },
	## FUNCTION etl:env($environment_variable_name): $string
	{ ns => core::NAMESPACE_URL,	name => 'env',		handle => \&_xsl_env },
	## FUNCTION etl:ifnull($obj1, $obj2, ...): $obj
	{ ns => core::NAMESPACE_URL,	name => 'ifnull',	handle =>\&_xsl_ifnull },
	## FUNCTION etl:if($test, $obj1, $obj2): $obj
	{ ns => core::NAMESPACE_URL,	name => 'if',		handle => \&_xsl_if },
	## FUNCTION etl:sleep($seconds): $numeric
	{ ns => core::NAMESPACE_URL,	name => 'sleep',	handle => \&_xsl_sleep },
	## FUNCTION etl:getenv($name, [, $default ]): $string
	{ ns => core::NAMESPACE_URL,	name => 'getenv',	handle => \&_xsl_getenv },
	## FUNCTION etl:lc($string): $string
	{ ns => core::NAMESPACE_URL,	name => 'lc',		handle => \&_xsl_lc },
	## FUNCTION etl:uc($string): $string
	{ ns => core::NAMESPACE_URL,	name => 'uc',		handle => \&_xsl_uc },
	## FUNCTION etl:trim($string): $string
	{ ns => core::NAMESPACE_URL,	name => 'trim',		handle => \&_xsl_trim },
	## FUNCTION etl:unaccent($string): $string
	{ ns => core::NAMESPACE_URL,	name => 'unaccent',	handle => \&_xsl_unaccent },
);
@FUNCTION_MAP = @FUNCTION_MAP_def;

1;
