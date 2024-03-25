#!/usr/bin/perl -w
# 
# The script schedules VIOS backups based on number in their hostname - odd or even. 
# The script creates an array with VIO servers and schdules backups between 15 minutes interval using at command.
# 
#
use strict;

my $target_vios = $ARGV[0];   # Odd or even
my $usage = "vios_backup_scheduler.pl even or odd";
die "Usage :$usage\n" if !$target_vios; 

my $backup_vios_script="/export/scripts/backup/backup_vios_nim.sh";
my @VIOS_LIST = `/usr/sbin/lsnim -t vios | awk '{print \$1}'`;
my (@even_vios,@odd_vios);
my $even_ref = \@even_vios;
my $odd_ref = \@odd_vios;

foreach (@VIOS_LIST) {
	chomp;
	if ( $_ =~ /^x.*?(\d\d)P/ ) {
		my $n = $1;
		$n =~ s/^0//;
		if ($n%2 == 1) {
		   push @odd_vios, $_;
		} else {
		   push @even_vios, $_;
		}
	}
}

sub schedule_ios_mksysb_backups
{
	my $target = shift;
	my @target_vioses = @$target;
	my $counter = 0;
	my $when = "now";

        foreach(@target_vioses) {
		my $increment = int($counter/10);
	        if ($increment != 0) {
			my $minutes = $increment*15;	
			$when .= " + $minutes minutes";
		}	
		my $command = "echo \"$backup_vios_script $_\" | at $when\n";
		system($command);
		$counter++;
		$when = "now";
	}
}

if ( $target_vios eq 'even' ) {
    	schedule_ios_mksysb_backups $even_ref;
} elsif ($target_vios eq 'odd' ) {
    	schedule_ios_mksysb_backups $odd_ref;
} else {
	die "Usage :$usage\n";
}

