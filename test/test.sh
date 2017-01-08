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

##############################################################################
function testall {
	$DOCK_COMP up -d --force-recreate --build
	sleep 2
	printf "Debug: curl\n";
	curl -i --data-binary @$THISDIR/$TESTPKGNAM localhost:8084/test/upload/
	printf "Debug: logs\n";
	$DOCK_COMP logs 
	printf "Debug: down\n";
	$DOCK_COMP down 
}

##############################################################################
function testclient {
	# Startup
	pushd $THISDIR >/dev/null
	rm -rf client cache repo >/dev/null
	mkdir -p client client/etc/pacman.d client/var/lib/pacman client/var/cache/pacman/pkg
	$DOCK_COMP up -d --force-recreate --build
	sleep 2

	##### Test: Uploading a package #####
	STARTTIME=$(date +%s)
	if [ -f repo/test/$TESTPKGNAM ]; then
		printf "Error - Package File %s exists before RUN\n" "repo/test/$TESTPKGNAM"
		return 1
	fi
	curl -i --data-binary @$TESTPKGNAM localhost:8084/test/upload/
	if ! cmp repo/test/os/x86_64/$TESTPKGNAM $TESTPKGNAM ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Package File %s corrupt of missing after upload\n" \
			"repo/test/os/x86_64/$TESTPKGNAM"
		return 1
	fi
	if ! [ -f repo/test/os/x86_64/test.db.tar.gz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Repo Database %s missing after upload\n" \
			"repo/test/test.db.tar.gz"
		return 1
	fi
	if ! [ -L repo/test/os/x86_64/test.db ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - Repo Database %s missing after upload\n" \
			"repo/test/test.db"
		return 1
	fi

	##### Test: Loading Repository index #####
	STARTTIME=$(date +%s)
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

	##### Test: Loading Package of custom repo #####
	STARTTIME=$(date +%s)
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


	##### Test: Loading a package from public #####
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
	if [ ! -f cache/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - missing cache file %s \n" \
			"cache/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz"
		return 1
	fi

	# Shutdown
	popd >/dev/null
	$DOCK_COMP down 

	printf "All Test succesfully passed.\n"
}

function testperl {
STARTTIME=$(date +%s)
$DOCK_COMP up -d --no-recreate --no-build
docker cp $THISDIR/../upload.pl pacmanrepo_pacman-repo_1:/usr/local/bin
$DOCK_COMP exec pacman-repo bash -c 'kill $(pidof /usr/bin/perl)'
$DOCK_COMP exec pacman-repo -d /usr/local/bin/upload.pl
curl -i --data-binary @$THISDIR/$TESTPKGNAM localhost:8084/test/upload/
docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
}

function testperllocal {
	cp -a $THISDIR/binutils-efi-2.27-1.90-x86_64.pkg.tar.xz $THISDIR/testpkgtemp
	$THISDIR/../upload.pl $THISDIR/testpkgtemp
	test -f $THISDIR/testpkgtemp && rm $THISDIR/testpkgtemp
}

export THISDIR=$(getDir)
export DOCK_COMP="docker-compose -f $THISDIR/docker-compose.yaml -p pacman-repo"
export TESTPKGNAM="binutils-efi-2.27-1.90-x86_64.pkg.tar.xz"
export PACMAN_OPT="-dd --noconfirm" 
export PACMAN_OPT="$PACMAN_OPT --root client"
export PACMAN_OPT="$PACMAN_OPT --config pacman.conf.pacman-repo-test"
export PACMAN_OPT="$PACMAN_OPT --cachedir client/var/cache/pacman/pkg"

perl -c $THISDIR/../upload.pl
if [ $? -ne 0 ]; then
	printf "Syntax Error in Perl. Aborting test.\n"
elif [ "$1" == "--perl" ]; then
	testperl
elif [ "$1" == "--perllocal" ]; then
	testperllocal
elif [ "$1" == "--client" ]; then
	testclient
else
	testall
fi
