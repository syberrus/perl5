package PodcheckUtils;
BEGIN {
    require './regen/regen_lib.pl';
}
use base qw( Exporter );
our @EXPORT_OK = qw(
    regen_sort_valid
    analyze_one_file
    non_regen_known_problems_notice
    final_notification
    regen_cleanup
    my_safer_print
    canonicalize
    test_count_discrepancy
    plan
    ok
    skip
    note
);
use File::Spec;

our $current_test = 0;
our $planned;
sub plan {
    my %plan = @_;
    $planned = $plan{tests} + 1;    # +1 for final test that files haven't
                                    # been removed
    print "1..$planned\n";
    return;
}

sub ok {
    my $success = shift;
    my $message = shift;

    chomp $message;

    $current_test++;
    print "not " unless $success;
    print "ok $current_test - $message\n";
    return $success;
}

sub skip {
    my $why = shift;
    my $n    = @_ ? shift : 1;
    for (1..$n) {
        $current_test++;
        print "ok $current_test # skip $why\n";
    }
    no warnings 'exiting';
    last SKIP;
}

sub note {
    my $message = shift;

    chomp $message;

    print $message =~ s/^/# /mgr;
    print "\n";
    return;
}

sub test_count_discrepancy {
    if ($planned && $planned != $current_test) {
        print STDERR
        "# Looks like you planned $planned tests but ran $current_test.\n";
    }
}

{ # Closure
    my $first_time = 1;

    sub output_thanks ($$$$) {  # Called when an issue has been fixed
        my $filename = shift;
        my $original_count = shift;
        my $current_count = shift;
        my $message = shift;

        $files_with_fixes{$filename} = 1;
        my $return;
        my $fixed_count = $original_count - $current_count;
        my $a_problem = ($fixed_count == 1) ? "a problem" : "multiple problems";
        my $another_problem = ($fixed_count == 1) ? "another problem" : "another set of problems";
        my $diff;
        if ($message) {
            $diff = <<EOF;
There were $original_count occurrences (now $current_count) in this pod of type
"$message",
EOF
        } else {
            $diff = <<EOF;
There are no longer any problems found in this pod!
EOF
        }

        if ($first_time) {
            $first_time = 0;
            $return = <<EOF;
Thanks for fixing $a_problem!
$diff
Now you must teach $0 that this was fixed.
EOF
        }
        else {
            $return = <<EOF
Thanks for fixing $another_problem.
$diff
EOF
        }

        return $return;
    }
}

sub regen_sort_valid {
    my ($regen, $valid_modules, $copy_fh) = @_;
    if ($regen) {
        foreach (sort { lc $a cmp lc $b } keys %{$valid_modules}) {
            my_safer_print($copy_fh, $_, "\n");
        }
    }
}

sub analyze_one_file {
    my ($filename, $filename_to_checker, $regen, $problems,
        $known_problems, $copy_fh, $pedantic, $line_length, $C_not_linked, $C_with_slash) = @_;

    my $these_problems = {};
    $these_problems = $problems->{$filename};
    my $canonical = canonicalize($filename);
    SKIP: {
        my $skip = $filename_to_checker->{$filename}->get_skip // "";

        if ($regen) {
            foreach my $message ( sort keys %{$these_problems}) {
                my $count;

                # Preserve a negative setting.
                if ($known_problems->{$canonical}{$message}
                    && $known_problems->{$canonical}{$message} < 0)
                {
                    $count = $known_problems->{$canonical}{$message};
                }
                else {
                    $count = @{$these_problems->{$message}};
                }
                my_safer_print($copy_fh, $canonical . "\t$message\t$count\n");
            }
            next;
        }

        skip($skip, 1) if $skip;
        my @diagnostics;
        my $thankful_diagnostics = 0;
        my $indent = '  ';

        my $total_known = 0;
        foreach my $message ( sort keys %{$these_problems}) {
            $known_problems->{$canonical}{$message} = 0
                                    if ! $known_problems->{$canonical}{$message};
            my $diagnostic = "";
            my $problem_count = scalar @{$these_problems->{$message}};
            $total_known += $problem_count;
            next if $known_problems->{$canonical}{$message} < 0;
            if ($problem_count > $known_problems->{$canonical}{$message}) {

                # Here we are about to output all the messages for this type,
                # subtract back this number we previously added in.
                $total_known -= $problem_count;

                $diagnostic .= $indent . qq{"$message"};
                if ($problem_count > 2) {
                    $diagnostic .= "  ($problem_count occurrences,"
			. " expected $known_problems->{$canonical}{$message})";
                }
                foreach my $problem (@{$these_problems->{$message}}) {
                    $diagnostic .= " " if $problem_count == 1;
                    $diagnostic .= "\n$indent$indent";
                    $diagnostic .= "$problem->{parameter}" if $problem->{parameter};
                    $diagnostic .= " near line $problem->{-line}";
                    $diagnostic .= " $problem->{comment}" if $problem->{comment};
                }
                $diagnostic .= "\n";
                $files_with_unknown_issues{$filename} = 1;
            } elsif ($problem_count < $known_problems->{$canonical}{$message}) {
               $diagnostic = output_thanks($filename, $known_problems->{$canonical}{$message}, $problem_count, $message);
               $thankful_diagnostics++;
            }
            push @diagnostics, $diagnostic if $diagnostic;
        }

        # The above loop has output messages where there are current potential
        # issues.  But it misses where there were some that have been entirely
        # fixed.  For those, we need to look through the old issues
        foreach my $message ( sort keys %{$known_problems->{$canonical}}) {
            next if $these_problems->{$message};
            next if ! $known_problems->{$canonical}{$message};
            next if $known_problems->{$canonical}{$message} < 0; # Preserve negs

            next if !$pedantic and $message =~ 
                /^(?:\Q$line_length\E|\Q$C_not_linked\E|\Q$C_with_slash\E)/;

            my $diagnostic = output_thanks($filename, $known_problems->{$canonical}{$message}, 0, $message);
            push @diagnostics, $diagnostic if $diagnostic;
            $thankful_diagnostics++ if $diagnostic;
        }

        my $output = "POD of $filename";
        $output .= ", excluding $total_known not shown known potential problems"
                                                                if $total_known;
        if (@diagnostics && @diagnostics == $thankful_diagnostics) {
            # Output fixed issues as passing to-do tests, so they do not
            # cause failures, but t/harness still flags them.
            $output .= " # TODO"
        }
        ok(@diagnostics == $thankful_diagnostics, $output);
        if (@diagnostics) {
            note(join "", @diagnostics,
            "See end of this test output for your options on silencing this");
        }

        delete $known_problems->{$canonical};
    }
    return $known_problems;
}

sub non_regen_known_problems_notice {
    my ($regen, $known_problems) = @_;
    if (! $regen
        && ! ok (keys %{$known_problems} == 0, "The known problems database includes no references to non-existent files"))
    {
        note("The following files were not found: "
             . join ", ", keys %{$known_problems});
        note("They will automatically be removed from the db the next time");
        note("  cd t; ./perl -I../lib porting/podcheck.t --regen");
        note("is run");
    }
}

sub final_notification {
    my ($files_with_unknown_issues, $files_with_fixes, $known_issues) = @_;
    my $how_to = <<EOF;
   run this test script by hand, using the following formula (on
   Un*x-like machines):
        cd t
        ./perl -I../lib porting/podcheck.t --regen
EOF

    if (%{$files_with_unknown_issues}) {
        my $were_count_files = scalar keys %{$files_with_unknown_issues};
        $were_count_files = ($were_count_files == 1)
                            ? "was $were_count_files file"
                            : "were $were_count_files files";
        my $message = <<EOF;

HOW TO GET THIS .t TO PASS

There $were_count_files that had new potential problems identified.
Some of them may be real, and some of them may be false positives because
this program isn't as smart as it likes to think it is.  You can teach this
program to ignore the issues it has identified, and hence pass, by doing the
following:

1) If a problem is about a link to an unknown module or man page that
   you know exists, re-run the command something like:
      ./perl -I../lib porting/podcheck.t --add_link MODULE man_page ...
   (MODULEs should look like Foo::Bar, and man_pages should look like
   bar(3c); don't do this for a module or man page that you aren't sure
   about; instead treat as another type of issue and follow the
   instructions below.)

2) For other issues, decide if each should be fixed now or not.  Fix the
   ones you decided to, and rerun this test to verify that the fixes
   worked.

3) If there remain false positive or problems that you don't plan to fix right
   now,
$how_to
   That should cause all current potential problems to be accepted by
   the program, so that the next time it runs, they won't be flagged.
EOF
        if (%files_with_fixes) {
            $message .= "   This step will also take care of the files that have fixes in them\n";
        }

        $message .= <<EOF;
   For a few files, such as perltoc, certain issues will always be
   expected, and more of the same will be added over time.  For those,
   before you do the regen, you can edit
   $known_issues
   and find the entry for the module's file and specific error message,
   and change the count of known potential problems to -1.
EOF

        note($message);
    } elsif (%{$files_with_fixes}) {
        note(<<EOF
To teach this test script that the potential problems have been fixed,
$how_to
EOF
        );
    }
}

sub regen_cleanup {
    my ($regen, $original_dir, $copy_fh) = @_;
    if ($regen) {
        chdir $original_dir || die "Can't change directories to $original_dir";
        close_and_rename($copy_fh);
    }
}

sub my_safer_print {    # print, with error checking for outputting to db
    my ($fh, @lines) = @_;

    if (! print $fh @lines) {
        my $save_error = $!;
        close($fh);
        die "Write failure: $save_error";
    }
}

# This is to get this to work across multiple file systems, including those
# that are not case sensitive.  The db is stored in lower case, Un*x style,
# and all file name comparisons are done that way.
sub canonicalize($) {
    my $input = shift;
    my ($volume, $directories, $file)
                    = File::Spec->splitpath(File::Spec->canonpath($input));
    # Assumes $volume is constant for everything in this directory structure
    $directories = "" if ! $directories;
    $file = "" if ! $file;
    $file = lc join '/', File::Spec->splitdir($directories), $file;
    $file =~ s! / /+ !/!gx;       # Multiple slashes => single slash

    # The db is stored without the special suffixes that are there in VMS, so
    # strip them off to get the comparable name.  But some files on all
    # platforms have these suffixes, so this shouldn't happen for them, as any
    # of their db entries will have the suffixes in them.  The hash has been
    # populated with these files.
    if ($^O eq 'VMS'
        && $file =~ / ( $vms_re ) $ /x
        && ! exists $special_vms_files{$file})
    {
        $file =~ s/ $1 $ //x;
    }
    return $file;
}

1;
