#!/usr/bin/perl -w

BEGIN {
    unshift @INC, "./lib";
}

use strict;
use warnings;
use feature 'unicode_strings';

use Carp;
use Config;
use Digest;
use File::Find;
use File::Spec;
use Scalar::Util;
use Text::Tabs;

BEGIN {
    if ( $Config{usecrosscompile} ) {
        print "1..0 # Not all files are available during cross-compilation\n";
        exit 0;
    }
    require 'regen/regen_lib.pl';
}

sub DEBUG { 0 };

=pod

=head1 NAME

add_link.pl - Teach podcheck.t that the C<MODULE>s or man pages actually
exist and silence any messages that links to them are broken.

=head1 SYNOPSIS


 ./perl Porting/add_link.pl MODULE ...

=cut

# VMS builds have a '.com' appended to utility and script names, and it adds a
# trailing dot for any other file name that doesn't have a dot in it.  The db
# is stored without those things.  This regex allows for these special file
# names to be dealt with.  It needs to be interpolated into a larger regex
# that furnishes the closing boundary.
my $vms_re = qr/ \. (?: com )? /x;


my $original_dir = File::Spec->rel2abs(File::Spec->curdir);
my $data_dir = File::Spec->catdir($original_dir, 't', 'porting');
my $known_issues = File::Spec->catfile($data_dir, 'known_pod_issues.dat');

my @files = @ARGV;
if (! @files) {
    croak "--add_link requires at least one module or man page reference";
}

my %valid_modules;      # List of modules known to exist outside us.

my $data_fh;
open $data_fh, '<:bytes', $known_issues or die "Can't open $known_issues";

my $HEADER = <<END;
# This file is the data file for $0.
# There are three types of lines.
# Comment lines are white-space only or begin with a '#', like this one.  Any
#   changes you make to the comment lines will be lost when the file is
#   regen'd.
# Lines without tab characters are simply NAMES of pods that the program knows
#   will have links to them and the program does not check if those links are
#   valid.
# All other lines should have three fields, each separated by a tab.  The
#   first field is the name of a pod; the second field is an error message
#   generated by this program; and the third field is a count of how many
#   known instances of that message there are in the pod.  -1 means that the
#   program can expect any number of this type of message.
END

my @existing_issues;


while (<$data_fh>) {    # Read the database
    chomp;
    next if /^\s*(?:#|$)/;  # Skip comment and empty lines
    if (/\t/) {
        push @existing_issues, $_;
        next;
    }
    else {  # Lines without a tab are modules known to be valid
        $valid_modules{$_} = 1
    }
}
close $data_fh;

# will need these subs
# open_new : regen/regen_lib.pl
# my_safer_print
# close_and_rename : regen/regen_lib.pl

my $copy_fh = open_new($known_issues);

# Check for basic sanity, and add each command line argument
foreach my $module (@files) {
    die "\"$module\" does not look like a module or man page"
        # Must look like (A or A::B or A::B::C ..., or foo(3C)
        if $module !~ /^ (?: \w+ (?: :: \w+ )* | \w+ \( \d \w* \) ) $/x;
    $valid_modules{$module} = 1
}
my_safer_print($copy_fh, $HEADER);
foreach (sort { lc $a cmp lc $b } keys %valid_modules) {
    my_safer_print($copy_fh, $_, "\n");
}

# The rest of the db file is output unchanged.
my_safer_print($copy_fh, join "\n", @existing_issues, "");

close_and_rename($copy_fh);
exit;

#########

sub my_safer_print {    # print, with error checking for outputting to db
    my ($fh, @lines) = @_;

    if (! print $fh @lines) {
        my $save_error = $!;
        close($fh);
        die "Write failure: $save_error";
    }
}

