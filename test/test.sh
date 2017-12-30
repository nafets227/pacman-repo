#!/bin/bash
#
# Test pacman-repo Container
#
# (C) Stefan Schallenberg
#

#-----------------------------------------------------------------------------
#----- Utilities functions ---------------------------------------------------
#-----------------------------------------------------------------------------

##############################################################################
function getDir {
	local THISDIR=$(dirname $BASH_SOURCE)
	THISDIR=$(realpath $THISDIR)
	echo $THISDIR
}

##############################################################################
function makePacmanConf {
	local rc=0
	local PACMAN_CONF=$CLIDIR/etc/pacman.conf

	printf "********** makePacmanConf $CLI_TYPE start ***********\n"

	mkdir -p \
		$CLIDIR/var/lib/pacman       \
		$CLIDIR/var/cache/pacman/pkg \
		$CLIDIR/etc/pacman.d

	cat >$PACMAN_CONF <<-EOF
		[options]
		HoldPkg      = pacman glibc
		CheckSpace

		SigLevel    = Required DatabaseOptional
		LocalFileSigLevel = Optional

		# Settings for test repositories in our architecture
		Architecture = $arch

		# Standard Values:
		#RootDir     = /
		#DBPath      = /var/lib/pacman/
		#CacheDir    = /var/cache/pacman/pkg/
		#LogFile     = /var/log/pacman.log
		#GPGDir      = /etc/pacman.d/gnupg/
		#HookDir     = /etc/pacman.d/hooks/

		RootDir      = $CLIDIR/
		DBPath       = $CLIDIR/var/lib/pacman/
		CacheDir     = $CLIDIR/var/cache/pacman/pkg/
		LogFile      = $CLIDIR/var/log/pacman.log
		GPGDir       = $CLIDIR/etc/pacman.d/gnupg/
		HookDir      = $CLIDIR/etc/pacman.d/hooks/

		[core]
		Server = $URL/\$repo/os/\$arch

		EOF

	# Add Test repository only for x86_64 since our testpackage is
	# only available on that architecture and any other architecture
	# would create errors when trying to load the database that will
	# not be initialised because no upload is executed.
	if [ $CLI_TYPE != "compat-armv6h" ] &&
	   [ $CLI_TYPE != "armv6h" ] ; then
		cat >>$PACMAN_CONF <<-EOF
		##### This is for testing our local repository
		[test]
		SigLevel = Optional # do not require signed packages or DBs
		Server = $URL/\$repo/os/\$arch
		EOF
	fi

	if [ $arch == "x86_64" ] ; then
		PKGURL="https://www.archlinux.org/packages/core/any/archlinux-keyring/download"
	elif [ $arch == "armv6h" ] ; then
		PKGURL="http://mirror.archlinuxarm.org/armv6h/core/archlinuxarm-keyring-20140119-1-any.pkg.tar.xz"
	else
		printf "ERROR: Unsupported architecture %s.\n" "$arch"
		return 1
	fi

	# we are keeping the /etc/pacman.d/gnupg in order to speed up.
	# Creating new keyrings would take a long time...
	# in other words: reuse existing local key if present
	if [ ! -e $CLIDIR/etc/pacman.d/gnupg/pubring.gpg ] ; then
		printf "********** makePacmanConf $CLI_TYPE GPG Init ***********\n"
		pacman-key --config $PACMAN_CONF --init
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
	else
		printf "********** makePacmanConf $CLI_TYPE GPG reuse ***********\n"
	fi

	#download package by hand because GPG keyring is not yet setup!
	curl -L \
		-o $CLIDIR/archlinux-keyring.pkg.tar.xz $PKGURL
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

	#install it using -U from local filesystem. This avoids GPG signature checks
	pacman $PACMAN_OPT \
		--config $PACMAN_CONF \
		--noscriptlet \
		-U $CLIDIR/archlinux-keyring.pkg.tar.xz
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

	# Now import the keys ...
	pacman-key \
		--config $PACMAN_CONF \
		--add $CLIDIR/usr/share/pacman/keyrings/archlinux*.gpg
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

	# ... and trust all of them.
	# Code snippet cpied from pacman-key --populate
	local -A trusted_ids
	while IFS=: read key_id _; do
		# skip blank lines, comments; there are valid in this file
		[[ -z $key_id || ${key_id:0:1} = \# ]] && continue
		
		# Mark thie ley to be lsigned
		trusted_ids[$key_id]=archlinux
	done < $CLIDIR//usr/share/pacman/keyrings/archlinux*-trusted
	
	pacman-key \
		--config $PACMAN_CONF \
		--lsign-key "${!trusted_ids[@]}"
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
		 
	gpg \
		--homedir $CLIDIR/etc/pacman.d/gnupg \
		--no-permission-warning \
		--import-ownertrust $CLIDIR/usr/share/pacman/keyrings/archlinux*-trusted
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

	printf "********** makePacmanConf $CLI_TYPE success ***********\n"
	
	return 0	
}

#-----------------------------------------------------------------------------
#----- Test cases ------------------------------------------------------------
#-----------------------------------------------------------------------------


##### Test: Uploading a package ##############################################
function testUpload {
	STARTTIME=$(date +%s)
	URL_UPLOAD="${1:-$URL/test/upload/}"
	printf "*********** testUpload start ($CLI_TYPE $URL_UPLOAD) **********\n"
	if [ ! -z "$CONT_REPO" ] && \
	   [ -f $CONT_REPO/test/os/x86_64/$TESTPKGNAM ] ; then
		printf "Error - Package File %s exists before RUN\n" "$CONT_REPO/test/os/x86_64/$TESTPKGNAM"
		return 1
	fi
	curl -Lfi $CURL_USER --data-binary @$TESTPKGNAM $URL_UPLOAD
	rc=$?
	if [ $rc -ne 0 ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - Upload to %s failed with RC=%s\n" "$URL_UPLOAD" "$rc"
		return 1
	fi
	if [ ! -z "$CONT_REPO" ] && ! cmp "$CONT_REPO/test/os/x86_64/$TESTPKGNAM" "$TESTPKGNAM" ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - Package File %s corrupt of missing after upload\n" \
			"$CONT_REPO/test/os/x86_64/$TESTPKGNAM"
		return 1
	fi
	if [ ! -z "$CONT_REPO" ] &&  ! [ -f $CONT_REPO/test/os/x86_64/test.db.tar.gz ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - Repo Database %s missing after upload\n" \
			"$CONT_REPO/test/os/x86_64/test.db.tar.gz"
		return 1
	fi
	if [ ! -z "$CONT_REPO" ] && ! [ -L $CONT_REPO/test/os/x86_64/test.db ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - Repo Database %s missing after upload\n" \
			"$CONT_REPO/test/os/x86_64/test.db"
		return 1
	fi

	printf "*********** testUpload success ($CLI_TYPE $URL_UPLOAD) **********\n"
	return 0
}

##### Test: Loading Repository index ($CLI_TYPE) #################################
function testIndex {
	STARTTIME=$(date +%s)
	printf "*********** testIndex start ($CLI_TYPE) **********\n"
	pacman -Syy $PACMAN_OPT --config $CLIDIR/etc/pacman.conf
	if [ $? -ne 0 ]	; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf "Error - pacman could not load the repositories through proxy\n"
		return 1
	fi
	if [ ! -f $CLIDIR/var/lib/pacman/sync/core.db ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - pacman did not write %s \n" \
			"$CLIDIR/var/lib/pacman/sync/core.db"
		return 1
	fi

	printf "*********** testIndex success ($CLI_TYPE) **********\n"
	return 0
}

##### Test: Loading Package of custom repo ####################################
function testDownload {
	STARTTIME=$(date +%s)
	printf "*********** testDownload start ($CLI_TYPE) **********\n"
	rm $CLIDIR/var/cache/pacman/pkg/$TESTPKGNAM >/dev/null 2>&1
	pacman -Sw $PACMAN_OPT --config $CLIDIR/etc/pacman.conf binutils-efi
	# This package does not exist in official repos, it was just uploaded
	if [ $? -ne 0 ]	; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf "Error - pacman could not load package binutils-efi\n"
		return 1
	fi
	if [ ! -f $CLIDIR/var/cache/pacman/pkg/$TESTPKGNAM ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - pacman did not write %s \n" \
			"$CLIDIR/var/cache/pacman/pkg/$TESTPKGNAM"
		return 1
	fi

	printf "*********** testDownload success ($CLI_TYPE) **********\n"
	return 0
}

##### Test: Loading a package from public ($CLI_TYPE) ############################
function testLoadPkg {
	printf "*********** testLoadPkg start ($CLI_TYPE) **********\n"
	STARTTIME=$(date +%s)
	rm $CLIDIR/var/cache/pacman/pkg/pacman-*-$arch.pkg.tar.xz >/dev/null 2>&1
	pacman -Sw $PACMAN_OPT --config $CLIDIR/etc/pacman.conf pacman
	if [ $? -ne 0 ]	; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf "Error - pacman could not load package pacman\n"
		return 1
	fi
	if [ ! -f $CLIDIR/var/cache/pacman/pkg/pacman-*-$arch.pkg.tar.xz ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - pacman did not write %s \n" \
			"$CLIDIR/var/cache/pacman/pkg/pacman-*-$arch.pkg.tar.xz"
		return 1
	fi
	if [ ! -z "$CONT_CACHE" ] && [ ! -f $CONT_CACHE/core/os/$arch/pacman-*-$arch.pkg.tar.xz ] ; then
		test -z "$CONT_LOG" || $CONT_LOG $STARTTIME
		printf  "Error - missing cache file %s \n" \
			"$CONT_CACHE/core/os/$arch/pacman-*-$arch.pkg.tar.xz"
		return 1
	fi

	printf "*********** testLoadPkg success ($CLI_TYPE) **********\n"
	return 0
}

##############################################################################
function testperllocal {
	cp -a \
		$THISDIR/binutils-efi-2.27-1.90-x86_64.pkg.tar.xz \
		$THISDIR/testpkgtemp \
		|| return 1
	LC_ALL=C $THISDIR/../upload.pl $THISDIR/testpkgtemp
	local rc=$?
	test -f $THISDIR/testpkgtemp && rm $THISDIR/testpkgtemp
	
	return $rc
}

##############################################################################
function testperlsyntax {
	perl -MFCGI -e ";" >/dev/null 2>&1
	if [ $? -eq 0 ] ; then
		printf "Checking Perl Syntax of upload.pl\n"
		LC_ALL=C perl -c $THISDIR/../upload.pl
		if [ $? -ne 0 ] ; then
			printf "Syntax Error in Perl. Aborting test.\n"
			return 1
		fi
	else
		printf "Not Checking Perl Syntax (perl of Perl Module FCGI not installed).\n"
	fi
}

#-----------------------------------------------------------------------------
#----- Local Setup using docker-compose --------------------------------------
#-----------------------------------------------------------------------------

##### LocalSetup: Start Containers ###########################################
function localsetup_start {
	export RESOLVER="$(sed -n -e 's/nameserver \(.*\)/\1/p' </etc/resolv.conf)"
	export NGINX_LOGLVL=""
	docker-compose \
		-f $THISDIR/docker-compose.yaml \
		-p pacman-repo \
		up \
		-d \
		--force-recreate \
		--build
	if [ $? -ne 0 ] ; then return 1 ; fi
		
	sleep 2
	
	return 0		
}

##### LocalSetup: Stop Containers ############################################
function localsetup_end {
	docker-compose \
		-f $THISDIR/docker-compose.yaml \
		-p pacman-repo \
		down 
}

##### LocalSetup: print log ##################################################
function localsetup_log {
	if [ -z "$1" ] ; then
		docker logs pacmanrepo_pacman-repo_1
	else 
		docker logs --since=$1 pacmanrepo_pacman-repo_1
	fi
}

#-----------------------------------------------------------------------------
#----- Test Sets -------------------------------------------------------------
#-----------------------------------------------------------------------------

##############################################################################
function testSetSmall {
	URL="http://localhost:8084"
	
	localsetup_start || return 1
	printf "Debug: curl\n";
	curl -Li $CURL_USER --data-binary @$THISDIR/$TESTPKGNAM $URL/test/upload/
	printf "Debug: logs\n";
	localsetup_log
	printf "Debug: down\n";
	localsetup_end 
}

##############################################################################
function testSetLocal {
	# Startup
	rm -rf $THISDIR/cache $THISDIR/repo >/dev/null
	
	localsetup_start || return 1

	testSetUrl \
		"http://localhost:8084" \
		"" \
		"$THISDIR/cache" \
		"$THISDIR/repo" \
		"localsetup_log"
	rc=$?

	# Shutdown
	localsetup_end

	return $rc
}
##############################################################################
function testSetUrlOneArch {
	# Execute all Test for One Architecture / setup
	# we expect some Environment Variables to be set correclty:
	#    - URL
	#    - CLIDIR
	#    - CLI_TYPE  (for handling anomalies)
	#    - arch
	#    - CURL_USER [optional]
	#    - CONT_CACHE [optional]
	#    - CONT_REPO [optional]
	printf  "Testing URL %s\n" "$URL"
	printf "\tClientDir: %s\n" "$CLIDIR"
	printf "\tArch: %s\n" "$arch"
    if [ ! -z "$CURL_USER" ] ; then 
		printf "\tUserID/PW: %s\n" "$CURL_USER"
	else
		printf "\tNo UserID/PW\n"; 
	fi
	if [ ! -z "$CONT_CACHE" ] ; then
		printf "\tCacheDir : %s\n" "$CONT_CACHE"
	else
		printf "\tNo CacheDir\n";
	fi
	if [ ! -z "$CONT_REPO" ] ; then
		printf "\tRepoDir : %s\n" "$CONT_REPO" 
	else
		printf "\tNo RepoDir\n";
	fi
	if [ ! -z "$CONT_LOG" ] ; then
		printf "\tLog Command : %s\n" "$CONT_LOG" 
	else
		printf "\tNo Log Command\n";
	fi

	if [ ! -z "$CURL_USER" ] ; then
		local CURL_USER="-u $CURL_USER"
	fi

	#
    # Now start the real tests
    #
	if [ "$CLI_TYPE" == "compat-x86_64" ] ; then
		testUpload "$URL/test/upload"
		rc=$?; if [ $rc -ne 0 ] ; then return $rc; fi
	elif [ "$CLI_TYPE" == "compat-armv6h" ] ; then
		# Uploading of armv6 in compatibility mode is not supported
		# so dont test it.
		/bin/true
	else
		testUpload "$URL.upload/test"
		rc=$?; if [ $rc -ne 0 ] ; then return $rc; fi
	fi

	testIndex
	rc=$?; if [ $rc -ne 0 ] ; then return $rc; fi

	if [ "$CLI_TYPE" != "compat-armv6h" ] &&
	   [ "$CLI_TYPE" != "armv6h" ] ; then
	   	# Our testpackage is available only for x86_64 architecture.
	   	# so we cannot test the download in armv6h architecture.
		testDownload
		rc=$?; if [ $rc -ne 0 ] ; then return $rc; fi
	fi

	testLoadPkg
	rc=$?; if [ $rc -ne 0 ] ; then return $rc; fi
		
	return 0
}

##############################################################################
function testSetUrl {

	# Reading Parameters
	BASE_URL="$1"
	BASE_CURL_USER="$2"
	BASE_CONT_CACHE="$3"
	BASE_CONT_REPO="$4"
	BASE_CONT_LOG="$5"

	for CLI_TYPE in compat-x86_64 compat-armv6h  x86_64 armv6h; do
		CLIDIR=$THISDIR/client.$CLI_TYPE

		#
		# Set correct environment for tests
		#
		local suburl subpath
		if [ "$CLI_TYPE" == "x86_64" ] ; then
			suburl="/archlinux"
			subpath="$suburl"
			arch="$CLI_TYPE"
		elif [ "$CLI_TYPE" == "armv6h" ] ; then
			suburl="/archlinuxarm"
			subpath="$suburl"
			arch="$CLI_TYPE"
		elif [ "$CLI_TYPE" == "compat-x86_64" ] ; then
			suburl=""
			subpath="/archlinux"
			arch="x86_64"
		elif [ "$CLI_TYPE" == "compat-armv6h" ] ; then
			suburl=""
			subpath="/archlinuxarm"
			arch="armv6h"
		else
			printf "Unknown Arch %s. Aborting\n" "$arch"
			rc=2; break
		fi

		URL="$BASE_URL$suburl"
		CONT_LOG="$BASE_CONT_LOG"
		
		if  [ ! -z "$BASE_CONT_CACHE" ] ; then
			CONT_CACHE=$BASE_CONT_CACHE$subpath
		else
			unset CONT_CACHE
		fi

		if [ ! -z "$BASE_CONT_REPO" ] ; then
			CONT_REPO=$BASE_CONT_REPO$subpath
			if [ -w "$CONT_REPO/test" ] ; then
				rm -rf $CONT_REPO/test
			elif [ -e "$CONT_REPO/test" ] ; then 
				printf "Error: Cannot write to %s. Aborting.\n" \
				"$CONT_REPO/test"
				rc=1; break;
			fi
		else
			unset CONT_REPO
		fi

		#
		# Setup Pacman Config
		#
		rm -rf \
			$CLIDIR/usr \
			$CLIDIR/var \
			$CLIDIR/archlinux*
		makePacmanConf "$CLI_TYPE"
		rc=$?
		if [ $rc -ne 0 ] ; then break; fi

		#
		# Now executre the real tests of one architecture
		#
		
		pushd $THISDIR >/dev/null
		testSetUrlOneArch
		rc=$?;
		popd >/dev/null
		
		if [ $rc -ne 0 ] ; then break; fi		

	done
		
	return $rc
}



#-----------------------------------------------------------------------------
#----- MAIN ------------------------------------------------------------------
#-----------------------------------------------------------------------------
export THISDIR=$(getDir)
export TESTPKGNAM="binutils-efi-2.27-1.90-x86_64.pkg.tar.xz"
export PACMAN_OPT="-dd --noconfirm" 

# check syntax to avoid actions that will fail anyhow.
testperlsyntax || exit 1

# Now execute tests
if [ "$1" == "--perllocal" ] ; then
	testperllocal
	rc=$?
elif [ "$1" == "--url" ] ; then
	shift
	testSetUrl $@
	rc=$?
else
	testSetLocal
	rc=$?
fi

if [ $rc -eq 0 ] ; then
	printf "All Test succesfully passed.\n"
else
	printf "Error in Tests.\n"
fi

exit $rc