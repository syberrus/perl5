#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl';	# for which_perl() etc
}

use Config;

my ($Null, $Curdir);
if(eval {require File::Spec; 1}) {
    $Null = File::Spec->devnull;
    $Curdir = File::Spec->curdir;
} else {
    die $@ unless is_miniperl();
    $Curdir = '.';
    diag("miniperl failed to load File::Spec, error is:\n$@");
    diag("\ncontinuing, assuming '.' for current directory. Some tests will be skipped.");
}


plan tests => 113;

my $Perl = which_perl();

$ENV{LC_ALL}   = 'C';		# Forge English error messages.
$ENV{LANGUAGE} = 'C';		# Ditto in GNU.

$Is_Amiga   = $^O eq 'amigaos';
$Is_Cygwin  = $^O eq 'cygwin';
$Is_Darwin  = $^O eq 'darwin';
$Is_Dos     = $^O eq 'dos';
$Is_MSWin32 = $^O eq 'MSWin32';
$Is_NetWare = $^O eq 'NetWare';
$Is_OS2     = $^O eq 'os2';
$Is_Solaris = $^O eq 'solaris';
$Is_VMS     = $^O eq 'VMS';
$Is_MPRAS   = $^O =~ /svr4/ && -f '/etc/.relid';
$Is_Android = $^O =~ /android/;

$Is_Dosish  = $Is_Dos || $Is_OS2 || $Is_MSWin32 || $Is_NetWare;

$Is_UFS     = $Is_Darwin && (() = `df -t ufs . 2>/dev/null`) == 2;

if ($Is_Cygwin && !is_miniperl) {
  require Win32;
  Win32->import;
}

my($DEV, $INO, $MODE, $NLINK, $UID, $GID, $RDEV, $SIZE,
   $ATIME, $MTIME, $CTIME, $BLKSIZE, $BLOCKS) = (0..12);

my $tmpfile = tempfile();
my $tmpfile_link = tempfile();

chmod 0666, $tmpfile;
unlink_all $tmpfile;
open(FOO, ">$tmpfile") || DIE("Can't open temp test file: $!");
close FOO;

open(FOO, ">$tmpfile") || DIE("Can't open temp test file: $!");

my($nlink, $mtime, $ctime) = (stat(FOO))[$NLINK, $MTIME, $CTIME];

# The clock on a network filesystem might be different from the
# system clock.
my $Filesystem_Time_Offset = abs($mtime - time); 

BEGIN { $^D = 4096; }

SKIP: {
    skip "No dirfd()", 9 unless $Config{d_dirfd} || $Config{d_dir_dd_fd};
    ok(opendir(DIR, "."), 'Can open "." dir') || diag "Can't open '.':  $!";
    # Calls Perl_pp_stat, which calls Perl_my_dirfd(), which should be single
    # stepped to see if it is returning a valid value.
    # FYI Calling sv_dump(sv) aborts

    ok(stat(DIR), "stat() on dirhandle works"); 
}
__END__
    ok(-d -r _ , "chained -x's on dirhandle"); 
    ok(-d DIR, "-d on a dirhandle works");

    # And now for the ambiguous bareword case
    {
	no warnings 'deprecated';
	ok(open(DIR, "TEST"), 'Can open "TEST" dir')
	    || diag "Can't open 'TEST':  $!";
    }
    my $size = (stat(DIR))[7];
    ok(defined $size, "stat() on bareword works");
    is($size, -s "TEST", "size returned by stat of bareword is for the file");
    ok(-f _, "ambiguous bareword uses file handle, not dir handle");
    ok(-f DIR);
    closedir DIR or die $!;
    close DIR or die $!;
}

{
    # RT #8244: *FILE{IO} does not behave like *FILE for stat() and -X() operators
    ok(open(F, ">", $tmpfile), 'can create temp file');
    my @thwap = stat *F{IO};
    ok(@thwap, "stat(*F{IO}) works");    
    ok( -f *F{IO} , "single file tests work with *F{IO}");
    close F;
    unlink $tmpfile;

    #PVIO's hold dirhandle information, so let's test them too.

    SKIP: {
        skip "No dirfd()", 9 unless $Config{d_dirfd} || $Config{d_dir_dd_fd};
        ok(opendir(DIR, "."), 'Can open "." dir') || diag "Can't open '.':  $!";
        ok(stat(*DIR{IO}), "stat() on *DIR{IO} works");
	ok(-d _ , "The special file handle _ is set correctly"); 
        ok(-d -r *DIR{IO} , "chained -x's on *DIR{IO}");

	# And now for the ambiguous bareword case
	{
	    no warnings 'deprecated';
	    ok(open(DIR, "TEST"), 'Can open "TEST" dir')
		|| diag "Can't open 'TEST':  $!";
	}
	my $size = (stat(*DIR{IO}))[7];
	ok(defined $size, "stat() on *THINGY{IO} works");
	is($size, -s "TEST",
	   "size returned by stat of *THINGY{IO} is for the file");
	ok(-f _, "ambiguous *THINGY{IO} uses file handle, not dir handle");
	ok(-f *DIR{IO});
	closedir DIR or die $!;
	close DIR or die $!;
    }
}

# [perl #71002]
{
    local $^W = 1;
    my $w;
    local $SIG{__WARN__} = sub { warn shift; ++$w };
    stat 'prepeinamehyparcheiarcheiometoonomaavto';
    stat _;
    is $w, undef, 'no unopened warning from stat _';
}

END {
    chmod 0666, $tmpfile;
    unlink_all $tmpfile;
}
