#!/usr/bin/perl

package upload;
use strict;
use warnings;

use FCGI;
use File::Basename;
use File::Path qw(make_path);
use File::Copy;

#debug
#use Data::Dumper;

my %Config = (
	name		=> 'Wert',
	socket		=> '/run/upload.sock',
	socketUser	=> 'http',
	socketGroup	=> 'http',
	template	=> '$root/$repo/os/$arch'
);


use constant OK => 0;
use constant ERR => 1;

sub handler_deprecated {
	#use nginx; # for HTTP_* status codes
	use constant HTTP_OK                        => 200;
	use constant HTTP_BAD_REQUEST               => 400;
	use constant HTTP_INTERNAL_SERVER_ERROR     => 500;
	
	my $r = shift;

	# calling perl directly from the upload location does not work, it will not respect
	# client_body_in_file_only. So we need to take an additional hop through an own server 
	# on a separate port and using proxy settings in the original location.
#	my $tmpfile = $r->request_body_file;
	my $tmpfile = $r->header_in("X-FILE");
	my $destfile = $r->filename;

	# Validate Input parameters
	if ( !isSafeString($tmpfile)) {
		$r -> log_error(0, 
			sprintf("invalid characters in tmpfile \"%s\"\n", $tmpfile));
		return HTTP_BAD_REQUEST;
	}

	if ( !isSafeString($destfile)) {
		$r -> log_error(0, 
			sprintf("invalid characters in destfile \"%s\"\n", $destfile));
		return HTTP_BAD_REQUEST;
	}

	$r->header_out("Debug-Info", sprintf("BackEnd checking filename \"%s\", tmpfile \"%s\"", $destfile, $tmpfile));

	my($dest_fnam, $dest_dir, $dest_ext) = fileparse($destfile);
	
	if ( ! -d $dest_dir ) {
		my $rc = mkdir($dest_dir ,0755);
		if ($rc != 0) {
			$r->log_error(0,
				sprintf("Could not create target directory %s\n", $dest_dir));
			$r->header_out("ExtendedError", "Could not create target directory");
			return HTTP_INTERNAL_SERVER_ERROR;
		}
	}

	my $rc = rename($tmpfile, $destfile);
	if($rc != 0)  {
		$r->log_error(0, 
			sprintf("Could not rename %s to %s", $tmpfile, $dest_dir));
		$r->header_out("ExtendedError", "Could not rename file");
		return HTTP_INTERNAL_SERVER_ERROR;
	}

	$r->send_http_header("text/html");
	$r->print("Success.\n");
	return 0;
}

##############################################################################
##### isSafeString ###########################################################
##############################################################################
sub isSafeString {
  my $Unsafe_RFC3986 = qr/[^A-Za-z0-9\-\._~\/]/;
  my ($text) = @_;
  my $result;
  return undef unless defined $text;

  if ( $text =~ $Unsafe_RFC3986 ) {
	  $result = OK;
  }
  else {
	  $result = ERR;
  }

  #debug
  #printf STDERR "isSafeString(\"%s\")=%d\n", $text, $result;

  return $result
}

##############################################################################
##### AnaylsePackage #########################################################
##############################################################################
sub analysePkg {
	my $pkgfile = shift;
	
	print "<h1>Package Meta-Data</h1>\n";

	my $output = qx(pacman -Qpi $pkgfile);
	# Example Output:
	# Name            : binutils-efi
	# Version         : 2.27-1.90
	# Description     : A set of programs to assemble and manipulate binary and object files
	# Architecture    : x86_64
	# ...

	my %pkgMeta;
	foreach my $line (split /[\r\n]+/, $output) {
		print "$line<br>\n";
		if ( $line =~ /^([\w ]+)\s*:\s*(.+)$/ ) {
			my $varname = $1;
			my $value = $2;
			# remove trailing blanks
			$varname =~ s/\s+$//;
			$value =~ s/\s+$//;

			#debug
			#print "$varname=$value\n";

			$pkgMeta{$varname} = $value;
			}
		else {
			print STDERR "Could not parse ouput-line from pacman: $line\n";
			print "Error parsing package file\n";
			return HTTP_BAD_REQUEST;
		}


	}
	print "<hr>\n";

	return %pkgMeta
}

##############################################################################
##### verifyPkg ##############################################################
##############################################################################
sub verifyPkg {
	my $pkgfile = shift;

	# Detect Extension
	# Pacman supported extension are define in man-page of makepkg.conf:
	#	PKGEXT=".pkg.tar.gz", SRCEXT=".src.tar.gz" 
	#	Sets the compression used when making compiled or source
	#	packages. Valid suffixes are .tar, .tar.gz, .tar.bz2, .tar.xz,
	#	.tar.lzo, .tar.lrz, and .tar.Z. Do not touch these unless you
	#	 know what you are doing. 
	# Detection of compression formats is taken from stackoverflow
	#	http://stackoverflow.com/questions/19120676/how-to-detect-type-of-compression-used-on-the-file-if-no-file-extension-is-spe)
	#	Gzip (.gz) format description, starts with 0x1f, 0x8b, 0x08
	#	bzip2 (.bz2) starts with 0x42, 0x5a, 0x68
	#	xz (.xz) format description, starts with 0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00
	#	lzo and lrz
	#	compress (.Z) starts with 0x1f, 0x9

	# @TODO implement checks (maybe only support .pkg.tar.xz)
	
       	# actually we skip checks and pretend everyhing is ok.
	return OK;

}
##############################################################################
##### uploadPackage ##########################################################
##############################################################################
sub uploadPkg {
	my $pkgfile = shift;
	my $root = shift;
	my $repo = shift;

	my %pkgMeta = analysePkg($pkgfile);

	##### identify target directory and filename #####
	my $arch=$pkgMeta{'Architecture'};
	my $template=$Config{'template'};

	my $dest_dir = $template;
	$dest_dir =~ s/\$root/$root/g;
	$dest_dir =~ s/\$repo/$repo/g;
	$dest_dir =~ s/\$arch/$arch/g;

	my $dest_fnam = "$pkgMeta{'Name'}-$pkgMeta{'Version'}-$pkgMeta{'Architecture'}";

	my $dest_ext = "pkg.tar.xz";


	my $destfile = "$dest_dir/$dest_fnam.$dest_ext";	

	#### now create directory and move file #####
	if ( ! -d $dest_dir ) {
		make_path( $dest_dir, {error => \my $err} );
		if (@$err) {
			print STDERR sprintf("Could not create target directory %s.\n", $dest_dir);
	        	for my $diag (@$err) {
				my ($file, $message) = %$diag;
				print STDERR sprintf("\t Error from make_path: %s - %s\n", $file, $message);
			}
			print "Could not create target directory\n";
			return ERR;
		}
		else {
			print STDERR sprintf("Created directory %s\n", $dest_dir);
		}
	}
	else {
		print STDERR sprintf("Using existing directory %s\n", $dest_dir);
	}


	my $rc = move($pkgfile, $destfile);
	if( $rc ne 1 ) {
		print STDERR sprintf("Could not rename %s to %s, RC=%s\n", $pkgfile, $destfile, $rc);
		print "Could not rename file\n";
		return ERR;
	}

	print "Success.\n";
	print "Your package has been successfully uploaded to $destfile\n";
	print STDERR "Uploaded to $destfile\n";
	return OK;
}

#############################################################################
##### printEnv ##############################################################
##############################################################################
sub printEnv {
	print "<h1>Perl Environment Variables</h1>\n";
	foreach my $key (sort(keys %ENV)) {
		print "$key = $ENV{$key}<br>\n";
	}
	print "<hr>\n";

	return OK;
}
#############################################################################
##### handleReq #############################################################
##############################################################################
sub handleReq {
	my $r = shift;

	print "Content-type:text/html\n\n";
	print "<html>\n";
	print "<head><title>Uploading of Pacman Packages</title></head>\n";
	print "<body>\n";

	printEnv;
  
	my $pkgfile = $ENV{"NGINX_REQUEST_BODY_FILE"};
	my $docroot = $ENV{'DOCUMENT_ROOT'};
	my $docuri = $ENV{'DOCUMENT_URI'};

	# Validate Input parameters
	if ( ! defined $pkgfile or ! length $pkgfile ) {
		print STDERR "No filename received in FastCGI variable NGINX_REQUEST_BODY_FILE\n";
		print "Internal Error - Missing Filename\n";
	}
	elsif ( !isSafeString($pkgfile)) {
		print STDERR 
			sprintf("invalid characters in tmpfile \"%s\"\n", $pkgfile);
		print "Internal Error - Invalid Filename\n";
	}
	elsif ( ! defined $docroot or ! length $docroot or !isSafeString($docroot)) {
		print STDERR "Invalid DOCUMENT_ROOT environment";
		if ( defined $docroot ) { 
			print STDERR " \"$docroot\"";
		}
		print STDERR "\n";
		print "Internal Error -DOCUMENT_ROOT\n";
	}
	elsif ( ! defined $docuri or ! length $docuri or !isSafeString($docuri)) {
		print STDERR "Invalid DOCUMENT_URI environment";
		if ( defined $docuri ) { 
			print STDERR " \"$docuri\"";
		}
		print STDERR "\n";
		print "Internal Error -DOCUMENT_URI\n";
	}
	elsif ( verifyPkg($pkgfile) ne OK ) {
		printf STDERR "Invalid package file $pkgfile supplied.\n";
		print "Invalid package File supplied - not in .pkg.tar.xz Format\n";
	}
	else { 
		# docuri should be like /<repo>/upload/
		if (  $docuri !~ /^\/(?<repo>.*)\/upload\/$/ ) {
			print STDERR
		       		sprintf("Invalid DOCUMENT_URI %s - not /<repo>/upload/\n",
				       	$docuri);
			print "Internal Error -DOCUMENT_URI subdir\n";
		}
		else
		{
	        	my $repo = $+{'repo'};

			uploadPkg $pkgfile, $docroot, $repo;
		}
	}

	print "</body>\n";
	print "</html>\n";

	return OK;
}


##############################################################################
##### main_fcgi ##############################################################
##############################################################################
sub main_fcgi {
	my $sock = FCGI::OpenSocket($Config{'socket'}, 10);

	my $uid = getpwnam $Config{'socketUser'};
	my $gid = getgrnam $Config{'socketGroup'};
	chown $uid, $gid, $Config{'socket'};

	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock);

	while($request->Accept() >= 0) {
	        handleReq $request;
	}

	$request->Finish();
	FCGI::CloseSocket($sock);

	return OK;
}

##############################################################################
##### Handlers ###############################################################
##############################################################################
BEGIN { 
  print STDERR "update.pl starting.\n";
  };

END {
  print STDERR "update.pl ending- RC=$?.\n";
  }

##############################################################################
##### Main ###################################################################
##############################################################################
my $pkgfile = shift;
my $root = shift;

if ( defined $pkgfile ) {
	print "Bypassing FastCGI and trying to upload $pkgfile.\n";
	if ( ! defined $root ) { $root = '/srv/archlinux'; }
	uploadPkg($pkgfile, $root, "test");
}
else {
	main_fcgi();
}

exit 0

__END__
