#!/usr/bin/perl -W

###############################################################################
##
## bkp-rsync.pl
##
## Richard Turnbull
##
## 23 February 2010
##
## Version 0.1dev  - requires rsync >v3.06 in /usr/local/bin/rsync
##                with patches - see http://www.bombich.com/mactips/rsync.html
##
##
###############################################################################


use strict;

use Net::Ping;
use Sys::Syslog;
use File::Temp qw/tempfile/;
use File::Copy;
use POSIX qw/strftime/;
use Mail::Send;

my $log_file;
my $home_directory = $ENV{'HOME'};
my $config_file = "$home_directory/.bkp-rsync/config";
my %Config;
my $have_errors=0;

print "Starting backup\n";
my $the_date = strftime('%Y-%m-%d-%H%M%S',localtime);

#get the various configuration items, place into hash %Config
&parse_config_file ($config_file, \%Config);

#print the config
#&print_config();

#is our backup server available?
if (ping_server()) {exit};

	
# open a temp file which we email to ourselves later
unless ($log_file = File::Temp->new() ) {
	my $have_errors=1;
	print "Cannot open logfile. exiting.";
	exit;
}

if (&mount_backup_share ())  {
	$have_errors=1;

	&mail_logfile();
	print "Backup failed - see log email\n";
	exit;
}
	
# mount the encrypted  disk image.
if (&attach_disk_image ())  {
	$have_errors=1;
	&mail_logfile();
	print "Backup failed - see log email\n";
	exit;
}


# run the rsync

my $source="$home_directory" . "$Config{source_dir}";
my $basepath="$Config{mountpoint}/$Config{backup_volume_name}";
my $destination="$basepath/backup-$the_date";

&logit ("rsyncing from $source to $destination");

my @args = ("/usr/local/bin/rsync", "2>&1",  "--archive",
			"--crtimes",
			"--hard-links",		
			"--acls",
			"--xattrs",
			"--one-file-system",
			"--protect-args",
			"--fileflags", 	
			"--force-change",
			"--link-dest=$basepath/current",
			"--exclude-from=$home_directory/.bkp-rsync/excludes",
			$source,
			$destination);
			
my @info = qx (@args);

# print output to logfile
foreach my $i (@info) {
	chomp $i;
	&logit( "rsync: $i");
}

unless ($? == 0)  {
	$have_errors=1;
	my $realerror = $? << 8;
	&logit ("rsync error: $realerror : $!"); 
	print "Backup failed - see log email\n";
	&mail_logfile();
	exit;
}


#reorg directory links

unless (unlink "$basepath/current")  {
	&logit("Cannot  unlink $basepath/current");
	$have_errors=1;
}

unless (symlink "$destination", "$basepath/current")  {
	&logit("Cannot  unlink $basepath/current");
	$have_errors=1;
}


if (&detach_disk_image ())  {
	$have_errors=1;
	&mail_logfile();
	print "Backup failed to detach disk image - see log email\n";
	exit;
}
	
# mail the logfile and end
my $success_message = "Backup completed with no errors";
&logit($success_message);
print "$success_message\n";
&mail_logfile();

# logfile will be deleted
exit;

####################################################################################################
#
# Subroutines
#
####################################################################################################

# mount the network share which contains our encrypted disk image
sub mount_backup_share {

	&logit ("mounting $Config{backup_host}/$Config{sharepoint} to $Config{mountpoint}");

	#print "$Config{mountpoint}/$Config{sharepoint}/$Config{backup_image_path}\n";

	# might be already mounted
	if ( -e "$Config{mountpoint}/$Config{sharepoint}/$Config{backup_image_path}")   {
		&logit ("$Config{sharepoint} already mounted to $Config{mountpoint}");
		return 0;
	}

# if this fails, then it's probably already there. which is ok you can't write to it anyway until you 
# mount stuff there - more mac magic-ness.
	mkdir "$Config{mountpoint}/$Config{sharepoint}";    

	my $password;
	
    unless ($password = &get_share_password)  {
    	&logit ("Share password not found in keychain");
    	return 1;
    }
    

	my @args = ("/sbin/mount_afp", "2>&1",
			"afp://$Config{fileserver_user}\:$password\@$Config{backup_host}/$Config{sharepoint}", 
			"$Config{mountpoint}/$Config{sharepoint}");
	

	system (@args);
	
	unless ($? == 0)  {
		my $realerror = $? << 8;
		&logit ("Could not mount backup share: $realerror : $!"); 
		return 1;
	}
	return 0;			
}			

sub unmount_backup_share  {

	&logit ("Unmounting $Config{mountpoint}/$Config{sharepoint}");
	
	my @args = ("/sbin/umount", "$Config{mountpoint}/$Config{sharepoint}");

	system (@args);
	
	unless ($? == 0)  {
		my $realerror = $? << 8;
		&logit ("Could not unmount $Config{mountpoint}$Config{sharepoint}: $realerror : $!");
		return 1;
	}
	
	return 0;
}

sub attach_disk_image {

	&logit ("Attaching $Config{mountpoint}/$Config{sharepoint}/$Config{backup_image_path}");
	
	my $password;
	unless ($password = &get_image_password)  {
    	&logit ("disk image password not found in keychain");
    	return 1;
    }
				
	my @args = ("/usr/bin/hdiutil",  "attach", "-nobrowse"
				"\"$Config{mountpoint}/$Config{sharepoint}/$Config{backup_image_path}\"", "2>&1");
							
	my @info = qx (@args);

	unless ($? == 0)  {
		my $realerror = $? << 8;
		&logit ("Could not attach $Config{backup_image_path}: $realerror: $!");
		return 1;
	}
 
	 	foreach my $i (@info) {
		chomp $i;
		&logit( "hdiutil: $i");
	}

	return 0;

}


sub detach_disk_image {

	&logit ("Detaching $Config{mountpoint}/$Config{backup_volume_name}");
	
	my @args = ("/usr/bin/hdiutil",  "detach", "$Config{mountpoint}/$Config{backup_volume_name}");	
	
	system (@args);
	
	unless ($? == 0)  {
		my $realerror = $? << 8;
		&logit ("Could not detach $Config{mountpoint}/$Config{backup_volume_name}: $realerror: $!");
		return 1;
	}

	return 0

}

# do we have a backup server? 

sub ping_server {
	my $ping_server = Net::Ping->new();
	my $return_code = 0;
	unless ($ping_server->ping($Config{backup_host})) {
		&logit (1, "$Config{backup_host} not alive");
		$return_code = 1;
	}
	$ping_server->close;
	return $return_code;
}


# mails logfile to whomever
sub mail_logfile {

	my $mail_subject;
	print "Mailing logfile\n";
	seek $log_file, 0, 0 or die "cannot seek";
	
	if ($have_errors) {
		$mail_subject= "bkp-rsync (errors): $the_date";
	}
	else
	{
		$mail_subject= "bkp-rsync: $the_date";
	}
	
	my $mail = new Mail::Send Subject=>$mail_subject, To=>"$Config{mail_logfile_to}";
	my $mail_body_fh = $mail->open;
	
	while (<$log_file>)  {
		print $mail_body_fh "bkp-rsync> $_";
	}
	
	$mail_body_fh->close;
	
}

# Parses configuration file
# Takes $file - the file name, \@Config - a hash of the config
sub parse_config_file {

	my ($config_line, $Name, $Value);	

    my ($File, $Config) = @_;

    if (!open (CONFIG, "$File")) {
        &logit ("ERROR: Config file not found : $File");
        &mail_log_file();
        exit(0);
    }

    while (<CONFIG>) {
        $config_line=$_;
        chop ($config_line);          # Get rid of the trailling \n
        $config_line =~ s/^\s*//;     # Remove spaces at the start of the line
        $config_line =~ s/\s*$//;     # Remove spaces at the end of the line
       
        if ( ($config_line !~ /^#/) && ($config_line ne "") ){    # Ignore lines starting with # and blank lines
            ($Name, $Value) = split (/=/, $config_line);          # Split each line into name value pairs
            $$Config{$Name} = $Value;                             # Create a hash of the name value pairs
        }
    }

    close(CONFIG);
}

sub get_share_password  {

	my $password = `/usr/bin/security 2>&1 find-internet-password -a "$Config{fileserver_user}" -s "$Config{file_server_srvr}" -g | grep password:`;
	chomp $password;
	
	$password  =~ /^password: "(.*)"$/;
	
	return $1;
}

sub get_image_password  {

	my $password = `/usr/bin/security 2>&1 find-generic-password -a $Config{backup_image_account}  -g | grep password:`;
	
	chomp $password;
	
	$password  =~ /^password: "(.*)"$/ ;

	return $1;
}

# Writes stuff to log
sub logit {
	
	my $message = shift;
	print $log_file "$message\n";
	
}

sub print_config  {
	foreach my $Config_key (keys %Config) {
		print "$Config_key = $Config{$Config_key}\n";
	}	
}

