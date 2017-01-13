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
function makePacmanConf {
	arch=${1-"x86_64"}
	rc=0

	mkdir -p \
		$THISDIR/client.$arch/var/lib/pacman       \
		$THISDIR/client.$arch/var/cache/pacman/pkg
	# we are keeping the /etc/pacman.d/gnupg in order to speed up.
	# Creating new keyrings would take a long time...
	#	$THISDIR/client.$arch/etc/pacman.d/gnupg
	# We are not creating it either, because if this dir does not exist
	# it will trigger key generation below.

	cat >$THISDIR/pacman.$arch.conf <<-EOF
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

	RootDir      = $THISDIR/client.$arch
	DBPath       = $THISDIR/client.$arch/var/lib/pacman/
	CacheDir     = $THISDIR/client.$arch/var/cache/pacman/pkg/
	GPGDir       = $THISDIR/client.$arch/etc/pacman.d/gnupg/

	[core]
	Server = $URL/\$repo/os/\$arch

	[extra]
	Server = $URL/\$repo/os/\$arch

	[community]
	Server = $URL/\$repo/os/\$arch
	EOF

	# Add Test repository only for x86_64 since our testpackage is
	# only available on that architecture and any other architecture
	# would create errors when trying to load the database that will
	# not be initialised because no upload is executed.
	if [ $arch == "x86_64" ] ; then
		cat >>$THISDIR/pacman.$arch.conf <<-EOF

		##### This is for testing our local repository
		[test]
		SigLevel = Optional # do not require signed packages or DB´s
		Server = $URL/\$repo/os/\$arch
		EOF
	fi

	if [ ! -d $THISDIR/client.$arch/etc/pacman.d/gnupg ] ; then
		STARTTIME=$(date +%s)
		printf "********** InitPacman $arch start ***********\n"
		mkdir -p $THISDIR/client.$arch/etc/pacman.d/gnupg
		# Initialize Pacman Signature DB

		pacman-key --config $THISDIR/pacman.$arch.conf --init
		rc=$?
		if [ $rc -ne 0 ] ; then
			dummy=bla
		elif [ $arch == "x86_64" ] ; then
			pacman-key --config $THISDIR/pacman.$arch.conf --populate archlinux || return 1
			rc=$?
		else
			##### Install archlinuxarm Keyring #####
			#get final URL after many redirects and download it
			FINALURL=$( \
				curl -I -JL https://www.archlinux.org/packages/core/any/archlinux-keyring/download | \
				sed -n 's/^Location: \(.*\)$/\1/p' | \
				tail -1 |\
				sed 's:[\n\r]::g' ) && \
			PKGFILE=$THISDIR/client.$arch/$(basename $FINALURL) && \
			curl -o $PKGFILE $FINALURL && \
			pacman -U $PACMAN_OPT $PKGFILE && \
			pacman-key --config $THISDIR/pacman.$arch.conf --populate archlinuxarm
			rc=$?
		fi
		if [ $rc -eq 0 ]; then
			printf "********** InitPacman $arch success ***********\n"
		else
			docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
			printf "********** InitPacman $arch Error ***********\n"
			return 1
		fi
	fi
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

##### Test: Loading x86 Repository index #####################################
function testX86Index {
	STARTTIME=$(date +%s)
	printf "*********** testX86Index start **********\n"
	pacman -Syy $PACMAN_OPT --config $THISDIR/pacman.x86_64.conf
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load the repositories through proxy\n"
		return 1
	fi
	if [ ! -f client.x86_64/var/lib/pacman/sync/community.db ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client.x86_64/var/lib/pacman/sync/community.db"
		return 1
	fi

	printf "*********** testX86Index success **********\n"
	return 0
}

##### Test: Loading ARM Repository index #####################################
function testArmIndex {
	STARTTIME=$(date +%s)
	printf "*********** testArmIndex start **********\n"
	pacman -Syy --arch armv6h $PACMAN_OPT --config $THISDIR/pacman.armv6h.conf
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load the repositories through proxy\n"
		return 1
	fi
	if [ ! -f client.armv6h/var/lib/pacman/sync/community.db ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client.armv6h/var/lib/pacman/sync/community.db"
		return 1
	fi

	printf "*********** testArmIndex success **********\n"
	return 0
}

##### Test: Loading Package of custom repo ####################################
function testDownload {
	STARTTIME=$(date +%s)
	printf "*********** testDownload start **********\n"
	pacman -Sw $PACMAN_OPT --config $THISDIR/pacman.x86_64.conf binutils-efi
	# This package does not exist in official repos, it was just uploaded
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load package binutils-efi\n"
		return 1
	fi
	if [ ! -f client.x86_64/var/cache/pacman/pkg/$TESTPKGNAM ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client.x86_64/var/cache/pacman/pkg/$TESTPKGNAM"
		return 1
	fi

	printf "*********** testDownload success **********\n"
	return 0
}

##### Test: Loading a X86 package from public ################################
function testLoadX86Pkg {
	STARTTIME=$(date +%s)
	printf "*********** testLoadX86Pkg start **********\n"
	pacman -Sw $PACMAN_OPT --config $THISDIR/pacman.x86_64.conf pacman
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load package pacman\n"
		return 1
	fi
	if [ ! -f client.x86_64/var/cache/pacman/pkg/pacman-*-x86_64.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client.x86_64/var/cache/pacman/pkg/pacman-*-x86_64.pkg.tar.xz"
		return 1
	fi
	if [ ! -z "$COMP_CACHE" ] && [ ! -f $COMP_CACHE/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - missing cache file %s \n" \
			"$COMP_CACHE/core/os/x86_64/pacman-*-x86_64.pkg.tar.xz"
		return 1
	fi

	printf "*********** testLoadX86Pkg success **********\n"
	return 0
}

##### Test: Loading a ARM package from public ################################
function testLoadArmPkg {
	STARTTIME=$(date +%s)
	printf "*********** testLoadArmPkg start **********\n"
	pacman -Sw $PACMAN_OPT --config $THISDIR/pacman.armv6h.conf pacman
	if [ $? -ne 0 ]	; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf "Error - pacman could not load package pacman\n"
		return 1
	fi
	if [ ! -f client.armv6h/var/cache/pacman/pkg/pacman-*-armv6h.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - pacman did not write %s \n" \
			"client.armv6h/var/cache/pacman/pkg/pacman-*-armv6h.pkg.tar.xz"
		return 1
	fi
	if [ ! -z "$COMP_CACHE" ] && [ ! -f $COMP_CACHE/core/os/armv6h/pacman-*-armv6h.pkg.tar.xz ] ; then
		docker logs --since=$STARTTIME pacmanrepo_pacman-repo_1
		printf  "Error - missing cache file %s \n" \
			"$COMP_CACHE/core/os/armv6h/pacman-*-armv6h.pkg.tar.xz"
		return 1
	fi

	printf "*********** testLoadArmPkg success **********\n"
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
	for arch in x86_64 armv6h; do
		makePacmanConf "$arch"
		rc=$?
		if [ $rc -ne 0 ] ; then return $rc; fi
	done

	# Tests
	testUpload && \
	testX86Index && \
	testLoadX86Pkg && \
	testDownload && \
	testArmIndex && \
	testLoadArmPkg
	rc=$?

	# Shutdown
	popd >/dev/null

	return $rc
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

# default values
URL="http://localhost:8084"
CURL_USER=""

# check syntax to avoid actions that will fail anyhow.
perl -c $THISDIR/../upload.pl
if [ $? -ne 0 ]; then
	printf "Syntax Error in Perl. Aborting test.\n"
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
