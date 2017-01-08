#!/bin/bash
#
# Test pacman-repo Container
#
# (C) Stefan Schallenberg
#

##############################################################################
function getDir {
	local THISDIR=$(dirname $BASH_SOURCE)
	THISDIR=$(realpath $THISDIR)
	echo $THISDIR
}

##### Test: Uploading a package ##############################################
function testUpload {
	STARTTIME=$(date +%s)
	printf "*********** testUpload start **********\n"
	if [ -f repo/test/$TESTPKGNAM ]; then
		printf "Error - Package File %s exists before RUN\n" "repo/test/$TESTPKGNAM"
		return 1
	fi
	curl -i $CURL_USER --data-binary @$TESTPKGNAM $URL/test/upload/
	if [ ! -z "$CONT_REPO" ] && ! cmp $CONT_REPO/test/os/x86_64/$TESTPKGNAM $TESTPKGNAM ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Package File %s corrupt of missing after upload\n" \
			"$CONT_REPO/test/os/x86_64/$TESTPKGNAM"
		return 1
	fi
	if [ ! -z "$CONT_REPO" ] &&  ! [ -f $CONT_REPO/test/os/x86_64/test.db.tar.gz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Repo Database %s missing after upload\n" \
			"$CONT_REPO/test/test.db.tar.gz"
		return 1
	fi
	if [ ! -z "$CONT_REPO" ] && ! [ -L $CONT_REPO/test/os/x86_64/test.db ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Repo Database %s missing after upload\n" \
			"$CONT_REPO/test/test.db"
		return 1
	fi

	printf "*********** testUpload success **********\n"
	return 0
}

##### Test: Loading Repository index #########################################
function testIndex {
	STARTTIME=$(date +%s)
	printf "*********** testIndex start **********\n"
	pacman -Syy $PACMAN_OPT
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load the repositories through proxy\n"
		return 1
	fi
	if [ ! -f client/var/lib/pacman/sync/community.db ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client/var/lib/pacman/sync/community.db"
		return 1
	fi

	printf "*********** testIndex success **********\n"
	return 0
}

##### Test: Loading Package of custom repo ####################################
function testDownload {
	STARTTIME=$(date +%s)
	printf "*********** testDownload start **********\n"
	pacman -Sw $PACMAN_OPT binutils-efi
	# This package does not exist in official repos, it was just uploaded
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load package pacman\n"
		return 1
	fi
	if [ ! -f client/var/cache/pacman/pkg/$TESTPKGNAM ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client/var/cache/pacman/pkg/$TESTPKGNAM"
		return 1
	fi

	return 0
}

##### Test: Loading a package from public #####################################
function testLoadPkg {
	STARTTIME=$(date +%s)
	pacman -Sw $PACMAN_OPT pacman
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load package pacman\n"
		return 1
	fi
	if [ ! -f client/var/cache/pacman/pkg/pacman-*-x86_64.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client/var/cache/pacman/pkg/pacman-*-x86_64.pkg.tar.xz"
		return 1
	fi
	if [ ! -z "$COMP_CACHE" ] && [ ! -f $COMP_CACHE/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - missing cache file %s \n" \
			"$COMP_CACHE/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz"
		return 1
	fi

	printf "*********** testDownload success **********\n"
	return 0
}

##############################################################################
function testall {
	$DOCK_COMP up -d --force-recreate --build
	sleep 2
	printf "Debug: curl\n";
	curl -i $CURL_USER --data-binary @$THISDIR/$TESTPKGNAM $URL/test/upload/
	printf "Debug: logs\n";
	$DOCK_COMP logs 
	printf "Debug: down\n";
	$DOCK_COMP down 
}

##############################################################################
function testclient {
	# Startup
	rm -rf $THISDIR/cache $THISDIR/repo >/dev/null
	$DOCK_COMP up -d --force-recreate --build
	sleep 2

	testurl "http://localhost:8084" "" "$THISDIR/cache" "$THISDIR/repo"
	rc=$?

	# Shutdown
	$DOCK_COMP down

	if [ $rc -eq 0 ]; then
	       printf "All Test succesfully passed.\n";
	fi
}

##############################################################################
function testurl {
	pushd $THISDIR >/dev/null

	# Reading Parameters
	URL="$1"
	CURL_USER="$2"
	CONT_CACHE="$3"
	CONT_REPO="$4"

	printf  "Testing URL %s\n" "$URL"
       	if [ ! -z "$CURL_USER" ] ; then 
		printf "\tUserID/PW: %s\n" "$CURL_USER"
	else    printf "\tNo UserID/PW\n"; fi
	if [ ! -z "$CONT_CACHE" ] ; then
		printf "\tCacheDir : %s\n" "$CONT_CACHE"
	else    printf "\tNo CacheDir\n"; fi
	if [ ! -z "$CONT_REPO" ] ; then
		printf "\tRepoDir : %s\n" "$CONT_REPO" 
	else    printf "\tNo RepoDir\n"; fi

	if [ ! -z "$CURL_USER" ] ; then CURL_USER="-u $CURL_USER"; fi
	
	# Setup Pacman Config
	test -d client || mkdir client
	rm -rf client/etc client/var >/dev/null
	mkdir -p client/etc/pacman.d client/var/lib/pacman client/var/cache/pacman/pkg
	cat >client/pacman.mirrorlist <<-EOF
	##
	## Arch Linux repository mirrorlist
	## for Testing
	##
	Server = $URL/\$repo/os/\$arch
	EOF
	cat >client/pacman.conf <<-EOF
	[options]
	HoldPkg     = pacman glibc
	Architecture = auto
	CheckSpace

	SigLevel    = Required DatabaseOptional
	LocalFileSigLevel = Optional

	[core]
	Include = $THISDIR/client/pacman.mirrorlist

	[extra]
	Include = $THISDIR/client/pacman.mirrorlist

	[community]
	Include = $THISDIR/client/pacman.mirrorlist

	##### This is for testing our local repository
	[test]
	SigLevel = Optional # do not require signed packages or DB´s
	Include = $THISDIR/client/pacman.mirrorlist
	EOF

	# Tests
	testUpload && \
	testIndex && \
	testDownload && \
	testLoadPkg
	rc=$?

	# Shutdown
	popd >/dev/null

	return $rc
}

##############################################################################
function testperl {
	STARTTIME=$(date +%s)
	$DOCK_COMP up -d --no-recreate --no-build
	docker cp $THISDIR/../upload.pl pacmanrepo_pacman-repo_1:/usr/local/bin
	$DOCK_COMP exec pacman-repo bash -c 'kill $(pidof /usr/bin/perl)'
	$DOCK_COMP exec pacman-repo -d /usr/local/bin/upload.pl
	curl -i $CURL_USER --data-binary @$THISDIR/$TESTPKGNAM $URL/test/upload/
	docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
}

##############################################################################
function testperllocal {
	cp -a $THISDIR/binutils-efi-2.27-1.90-x86_64.pkg.tar.xz $THISDIR/testpkgtemp
	$THISDIR/../upload.pl $THISDIR/testpkgtemp
	test -f $THISDIR/testpkgtemp && rm $THISDIR/testpkgtemp
}

#### Main ####################################################################
export THISDIR=$(getDir)
export DOCK_COMP="docker-compose -f $THISDIR/docker-compose.yaml -p pacman-repo"
export TESTPKGNAM="binutils-efi-2.27-1.90-x86_64.pkg.tar.xz"
export PACMAN_OPT="-dd --noconfirm" 
export PACMAN_OPT="$PACMAN_OPT --root client"
export PACMAN_OPT="$PACMAN_OPT --config client/pacman.conf"
export PACMAN_OPT="$PACMAN_OPT --cachedir client/var/cache/pacman/pkg"

# default values
URL="http://localhost:8084"
CURL_USER=""

# check syntax to avoid actions that will fail anyhow.
perl -c $THISDIR/../upload.pl
if [ $? -ne 0 ]; then
	printf "Syntax Error in Perl. Aborting test.\n"
elif [ "$1" == "--perl" ]; then
	testperl
elif [ "$1" == "--perllocal" ]; then
	testperllocal
elif [ "$1" == "--client" ]; then
	testclient
elif [ "$1" == "--url" ]; then
	shift
	testurl $@ || printf "All Test succesfully passed.\n"
else
	testall
fi
