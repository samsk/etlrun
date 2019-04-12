#!/bin/bash

AN=`readlink -f "$0"`
DN=`dirname "$AN"`;
SRCDIR="$DN/_source";
GIT_LIBS="https://github.com/htacg/tidy-html5"
PERL_MODULES="
 Try::Tiny Canary::Stability common::sense Module::Package Module::Build
 Try::Tiny Canary::Stability common::sense
 Text::CSV Text::CSV_XS
 JSON JSON::XS JSON::Parse
 URI:Escape
 XML::SAX XML::SAX::Base XML::LibXML XML::LibXSLT
 IO::HTML HTML::HTML5::Entities HTML::HTML5::Parser
 File::LibMagic LWP::UserAgent Digest::SHA1
 File::ShareDir
 Class::Inspector
 Archive::Extract
 Alien::Tidyp HTML::Tidy
 HTML::Valid
 DBI DBD::Pg DBD::SQLite
 Pg::hstore
 HTML::Selector::XPath
 +Scalar::Util
 Sub::Name
 XML::LibXML::Devel::SetLineNumber
 Types::Serialiser
 Text::Unidecode
 Unicode::Normalize"

export PERL_CANARY_STABILITY_NOPROMPT=1

# config
set -u;
set -x;

# check
if ! [ -d "$SRCDIR" ];
then	echo "$0: directory $SRCDIR does not exists !" >&2;
	exit 1;
fi;

# cleanup
rm -rf ~/.cpan/sources;

# create builddir
rm -rf "$SRCDIR/.tmp" &&
	mkdir "$SRCDIR/.tmp" || exit 1;

# clean installed files
[ -e ".incomplete" ] ||
	find $DN -mindepth 1 -maxdepth 1 -type d ! -name "_*" -print0 | xargs -0 rm -fr;

touch .incomplete;

pushd $SRCDIR || exit 1;

export PERL5LIB=$DN/lib:$DN/arch;
export LD_LIBRARY_PATH=$DN/lib;

# C libs
for mod in $GIT_LIBS
do
	modurl=$mod;
	mod=${mod##*/};

	{ echo -e "\n ===================================\n"\
	         "===> GIT $mod\n" \
	         "===================================\n"; } 2>/dev/null;

	mod_dir="$SRCDIR/.tmp/$mod";
	mod_build_dir="$mod_dir/.build";
	mkdir -p "$mod_dir" "$mod_build_dir";

	# build dir
	pushd "$SRCDIR/.tmp/$mod";
	git clone $modurl .build;

	pushd .build;

	[ -e "CMakeLists.txt" ] && cmake -D CMAKE_INSTALL_PREFIX=$DN .;
	make &&
		make install || exit 1

	popd;
	popd;
done;

# From CPAN
for mod in $PERL_MODULES;
do
	if [ "$mod" = "${mod#+}" ];
	then
		if perl -M$mod </dev/null &>/dev/null;
		then	echo "===> MODULE $mod: present";
			continue;
		fi;
	else
		mod="${mod#+}";
	fi;

	{ echo -e "\n ===================================\n"\
	         "===> MODULE $mod\n" \
	         "===================================\n"; } 2>/dev/null;

	mod_dir="$SRCDIR/.tmp/$mod";
	mod_build_dir="$mod_dir/.build";
	mkdir -p "$mod_dir" "$mod_build_dir";

	# build dir
	pushd "$SRCDIR/.tmp/$mod";

	# Alien-Tidyp (special)	
	if [ "$mod" = "Alien::Tidyp" ];
	then
		tar -xzf $SRCDIR/Alien-Tidyp-*.tar.gz -C .build &&
			pushd .build/* &&
			perl Build.PL &&
			./Build --srctarball=tidyp-1.05.tar.gz &&
			cp -rf ./blib/* $DN || exit 1
	else
		cpan -g "$mod";
		if ! ls * &>/dev/null;
		then
			echo "DOWNLOAD '$mod' FAILED.";
			exit 1;
		fi;

		tar -xf * -C .build &&
			pushd .build/* &&
			 perl ./Makefile.PL PREFIX=$DN &&
			make &&
			cp -rf ./blib/* $DN || exit 1
	fi;

	popd;
	popd;

	#rm -rf "$SRCDIR/.tmp/$mod";
done;

popd;

# fini
rm -rf $SRCDIR/.tmp $SRCDIR/.cpan;
rm -f .incomplete;
