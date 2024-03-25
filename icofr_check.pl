#!/usr/bin/perl -w
#
# 
# This scripts compare changes of priviliged users and groups , based on servers group and sudoers files fetch each quoter. Generated excel files as output.
#
#
use strict;
use Spreadsheet::WriteExcel;
use Getopt::Long;

## Global variables 
my $year = "0000";
my $quorter = "0";

my $usage = "Usage: $0 -y <YEAR> -q <QUORTER>\n";

GetOptions ( "year=i"	=> \$year,
	     "quorter=i" => \$quorter ) or die ($usage);

if ($year eq "0000" || $quorter eq "0"){
	die ($usage);
}

if ($quorter eq "0" || $quorter > 4){
	die ("Quorter must be 1,2,3 or 4\n");
}

## Set previous Quorter and Year based on provided
my ($year_old,$quorter_old);

if ($quorter eq "1") {
	$year_old = $year - 1;
	$quorter_old = 4;
} else {
	$year_old = $year;
	$quorter_old = $quorter - 1;
}


my $q = uc($year . "_Q" . $quorter);
my $q_old = uc($year_old . "_Q" . $quorter_old);
my $ICOFR_SERVERS = ("/icofrchecks/servers." . $year . "q" . $quorter);
my $ICOFR_SERVERS_OLD = ("/icofrchecks/servers." . $year_old . "q" . $quorter_old);
my $OUTPUT_DIRECTORY = "/icofrchecks/";
my $ssh = "/usr/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes";

die "Current ICOFR list file $ICOFR_SERVERS does not exist\n" if ! -e $ICOFR_SERVERS;
die "Previous ICOFR list file $ICOFR_SERVERS_OLD does not exist\n" if ! -e $ICOFR_SERVERS_OLD;

my (@servers,@serversold);


# Create two arrays. First with current icofr servers and second with previous
open(SRV, "$ICOFR_SERVERS");
while(<SRV>)
{
	chomp;
	push @servers, $_;
}
close(SRV);

open(SRVOLD, "$ICOFR_SERVERS_OLD");
while(<SRVOLD>)
{
	chomp;
	push @serversold, $_;
}
close(SRVOLD);

sub connectsrv($$$)
{
	my ($serv, $cmd, $ref_output) = @_;

	#open(CONN, "$ssh $serv \"sudo cat /etc/sudoers\" |");
	open(CONN, "$ssh $serv \"$cmd\" |");

	while(<CONN>)
	{
		chomp;
		push(@$ref_output,$_); 
	}

	close(CONN);

	return $ref_output;
}

sub get_files
{
	my ($cmd,$output_file,$srv);
	my @output;
	my $ref_output = \@output;

	foreach(@servers)
	{
	        $srv = $_;		
		print $srv, "\n";
		$cmd = "cat /etc/group";

		# !!!!!!!!!!!! ADD current Q in the path

		$output_file = $OUTPUT_DIRECTORY . $srv . "_" . "group";
		connectsrv($srv,$cmd,$ref_output);
		open(WG, "> $output_file");
		foreach(@output)
		{
			print WG $_, "\n";
		}
		close(WG);

		undef(@output);

		#$cmd = "/usr/bin/sudo cat /etc/sudoers";
		$cmd = "cat /etc/sudoers";
		$output_file = $OUTPUT_DIRECTORY . $srv . "_" . "sudoers";
		connectsrv($srv,$cmd,$ref_output);
		open(WG, "> $output_file");
                foreach(@output)
                {
                        print WG $_, "\n";
                }
                close(WG);

		undef(@output);

		$cmd = "cat /etc/passwd";
		$output_file = $OUTPUT_DIRECTORY . $srv . "_" . "passwd";
		connectsrv($srv,$cmd,$ref_output);
		open(WG, "> $output_file");
                foreach(@output)
                {
                        print WG $_, "\n";
                }
                close(WG);

		undef(@output);
	}
}

sub group_details($$)
{
	my $srv = shift;
	my $quarter = shift;
	my $DIR = $OUTPUT_DIRECTORY . $quarter . "/";
	my $group_file = $DIR . $srv . "_" . "group";
	my $sudo_file = $DIR . $srv . "_" . "sudoers";
	my $passwd_file = $DIR . $srv . "_" . "passwd";
	my (@line,@prvlusers,@ulist);
	my ($sudo_group,$members,$users,$usrgrp);
	my %groups;
	
	open(GRP, $group_file);
	while(<GRP>)
	{
		chomp;
		@line=split(/:/,$_);
		$members = $line[3];
		if (!$members) 
		{
			$members = "None";
		}
		$groups{$line[0]} = $members;
		#print "Group : ", $line[0], " Members: ", $members,"\n";	
	}
	close(GRP);

	open(SUDO, $sudo_file);
	while(<SUDO>)
	{
		chomp;
	        if ($_ =~ /^#/ || $_ =~ /^$/) {
                        next;
                }
		
		if ($_ =~ /^%(.*?)\s/ ) { 
			$sudo_group = $1;
			#if ($_ =~ /ALL=\(ALL\)/ || $_ =~ /ALL=\(root\)/) {
			if ($_ =~ /ALL=\(ALL\).*ALL/ || $_ =~ /ALL=\(root\).*ALL/) {
			    #print $sudo_group, "\n";	
			    $users = $groups{$sudo_group};
			    @ulist = split(/,/, $groups{$sudo_group}); 
			    #print "Group: ", $sudo_group, " has access to root. Users: ", $users, "\n";	
			    foreach (@ulist) {
				$usrgrp = $_ . "," . $sudo_group; 
				push (@prvlusers,$usrgrp);
			    }
			}
		}
		
	}
	close(SUDO);

	return @prvlusers;
}

sub is_existing_icofr_server($)
{
	my $srv = shift;
	my $output = 0;

	foreach(@serversold) {
		if ( $_ eq $srv ) {
			$output = 1;
			last;
		}
	}

	return $output;
}

sub get_new_or_deleted_users
{
	my $server = shift;	
	my ($exist_pq,$ugrp,$newu,$delu);
	my (@currq,@prevq,@newusers,@delusers);

	# Check if server was icofr in previous quarter
	@currq = group_details($server,$q);

	##print $server, " is an existing ICOFR server\n";	
	##print "Comparing users......\n"; 
	@prevq = group_details($server,$q_old);

	# Check if new users are added between the quarters
	foreach $ugrp (@currq) {
		$newu = 1;
		foreach(@prevq) {
			if ($ugrp eq $_) {
				$newu = 0;
				last;
			}
		}
		
		if ($newu == 1) {
			push(@newusers,$ugrp);
		}
	}

	# Check if users are deleted between the quarters
	foreach $ugrp (@prevq) {
		$delu = 1;
		foreach(@currq) {
			if ($ugrp eq $_) {
				$delu = 0;	
				last;
			}
		}
		
		if ($delu == 1) {
			##print "Old user: ", $ugrp, " is deleted\n";
			push(@delusers,$ugrp);
		}
	}

	return (\@newusers, \@delusers);
	
}

sub create_group_excel
{
	# Create a new excel file with content all the group files and comment which users are new
	#
	my $group_excel = "etcgroupreview_" . $q . ".xls";
	my $workbook = Spreadsheet::WriteExcel->new($group_excel);
	my $i = 1;
	my $format = $workbook->add_format(bg_color => 'yellow');
	$workbook->set_custom_color(10, '#DDD9C4');
	my $format1 = $workbook->add_format(bg_color => 10);
	$format1->set_border();
	my $format_redfont = $workbook->add_format(color => 'red');
	my $excel_sheet = "etcgroup_" . $q;
	my $worksheet = $workbook->add_worksheet($excel_sheet);
	$worksheet->set_column(0, 0,  100);
	$worksheet->set_column(1, 2,  20, $format1);
	$worksheet->set_column(3, 3,  30, $format1);
	$worksheet->write(0,0, 'System');
	$worksheet->write(0,1, 'Review by');
	$worksheet->write(0,2, 'CRQ Number');
	$worksheet->write(0,3, 'Comment');

	my ($privgrp,$r_newusers,$r_delusers);
	my (@newusers,@delusers);

	foreach my $server (@servers)
	{
		# Write head with server name in the excel
     		$worksheet->write($i, 0, $server, $format);
        	$i = $i + 2;

		#print $server;
		# Get list of privileged groups
		my @privileged_groups = group_details($server,$q);

	        # Check if server exist in previous quarter
                my $exist_pq = is_existing_icofr_server($server);

		if ($exist_pq == 1) {
			#print $server, "\n";
			($r_newusers,$r_delusers) = get_new_or_deleted_users($server);
		} else {
			print $server, " is a new ICOFR server\n";	
		}

		
		# Open group file and dump it into excel
		my $r_groupfile = dump_file_into_array($server,"group");

		foreach my $line (@{$r_groupfile}) {
                	$worksheet->write($i,0,$line);
			my @group_line = split(/:/, $line);
			foreach my $k (@privileged_groups) {
				my @prv_grp = split(/\,/, $k);
				if ($prv_grp[1] eq $group_line[0]) {
					$privgrp = 1;
					if ($exist_pq) {
						@newusers = grep(/$prv_grp[1]/,@{$r_newusers});
						@delusers = grep(/$prv_grp[1]/,@{$r_delusers});
					}
				}	
			}

			if ($privgrp) {
				my $comment = "Priviliged group ";	
				#$worksheet->write($i,3,"Privileged group");
				if (@newusers) {
					my $nw = "Added : "; 
					foreach(@newusers) {
						my @u = split(/,/, $_);
						$nw .= $u[0] . " "; 
					}
					$comment .= $nw;
				}

				if (@delusers) {
					my $dw = "Deleted : "; 
					foreach(@delusers) {
						my @u = split(/,/, $_);
						$dw .= $u[0] . " "; 
					}
					$comment .= $dw;
				}
				#print $comment, "\n";
				$worksheet->write($i,3,$comment);
			}
	

			undef($privgrp);
                	$i++;
		}
		undef(@newusers);
		undef(@delusers);
		undef($r_newusers);
		undef($r_delusers);

		$i++;
	}

	$workbook->close();
}

sub dump_file_into_array
{
	my $server = shift;
	my $file_type = shift;
	my @output;

	my $file_name = $OUTPUT_DIRECTORY . $q . "/" . $server . "_" . $file_type;
	open(F, "$file_name");
	while(<F>) 
	{
		push(@output,$_);
	}
	close(F);

	return \@output;
}

sub create_sudoers_excel
{
	$OUTPUT_DIRECTORY = $OUTPUT_DIRECTORY . $q . "/";
	my $sudoers_excel = "Sudoreview_" . $q . ".xls";
	my $workbook = Spreadsheet::WriteExcel->new($sudoers_excel);
	my $format = $workbook->add_format(bg_color => 'yellow');
	$workbook->set_custom_color(10, '#B8CCE4');
	my $format1 = $workbook->add_format(bg_color => 10);
	$format1->set_border();

	my $i = 1;
	my ($srv,$worksheet);

	foreach $srv (@servers)
	{
        	$worksheet = $workbook->add_worksheet($srv);
        	$worksheet->set_column(0, 0,  100);
        	$worksheet->set_column(1, 3,  20, $format1);
        	$worksheet->write(0,0, 'System');
        	$worksheet->write(0,1, 'Review by');
        	$worksheet->write(0,2, 'CRQ Number');
        	$worksheet->write(0,3, 'Comment');
        	my $sudoers_file = $OUTPUT_DIRECTORY . $srv . "_sudoers";
        	$worksheet->write($i, 0, $srv);
        	$i = $i + 2;

        	open(F, "$sudoers_file");
        	while(<F>)
        	{
                	$worksheet->write($i,0,$_);
                	$i++;
        	}
        	$i = $i + 2;
        	close(F);
        	$i = 1;
	}

}

sub main
{
	create_group_excel;
	create_sudoers_excel;
	#get_files;
	#analyze_users
	#foreach $srv (@servers) {
	#		my @currtmp = group_details($srv,"2018_Q2");
	#}
}

main
