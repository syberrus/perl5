#!./perl -w
#
# testsuite for Data::Dumper
#

BEGIN {
    require Config; import Config;
    if ($Config{'extensions'} !~ /\bData\/Dumper\b/) {
	print "1..0 # Skip: Data::Dumper was not built\n";
	exit 0;
    }
}

# Since Perl 5.8.1 because otherwise hash ordering is really random.
local $Data::Dumper::Sortkeys = 1;

use Data::Dumper;
use Config;
my $Is_ebcdic = defined($Config{'ebcdic'}) && $Config{'ebcdic'} eq 'define';

$Data::Dumper::Pad = "#";
my $TMAX;
my $XS;
my $TNUM = 0;
my $WANT = '';

sub TEST {
  my $string = shift;
  my $name = shift;
  my $t = eval $string;
  ++$TNUM;
  $t =~ s/([A-Z]+)\(0x[0-9a-f]+\)/$1(0xdeadbeef)/g
    if ($WANT =~ /deadbeef/);
  if ($Is_ebcdic) {
    # these data need massaging with non ascii character sets
    # because of hashing order differences
    $WANT = join("\n",sort(split(/\n/,$WANT)));
    $WANT =~ s/\,$//mg;
    $t    = join("\n",sort(split(/\n/,$t)));
    $t    =~ s/\,$//mg;
  }
  $name = $name ? " - $name" : '';
  print( ($t eq $WANT and not $@) ? "ok $TNUM$name\n"
    : "not ok $TNUM$name\n--Expected--\n$WANT\n--Got--\n$@$t\n");

  ++$TNUM;
  if ($Is_ebcdic) { # EBCDIC.
    if ($TNUM == 311 || $TNUM == 314) {
      eval $string;
    } else {
      eval $t;
    }
  } else {
    eval "$t";
  }
  print $@ ? "not ok $TNUM\n# \$@ says: $@\n" : "ok $TNUM\n";

  $t = eval $string;
  ++$TNUM;
  $t =~ s/([A-Z]+)\(0x[0-9a-f]+\)/$1(0xdeadbeef)/g
    if ($WANT =~ /deadbeef/);
  if ($Is_ebcdic) {
    # here too there are hashing order differences
    $WANT = join("\n",sort(split(/\n/,$WANT)));
    $WANT =~ s/\,$//mg;
    $t    = join("\n",sort(split(/\n/,$t)));
    $t    =~ s/\,$//mg;
  }
  print( ($t eq $WANT and not $@) ? "ok $TNUM\n"
    : "not ok $TNUM\n--Expected--\n$WANT\n--Got--\n$@$t\n");
}

sub SKIP_TEST {
  my $reason = shift;
  ++$TNUM; print "ok $TNUM # skip $reason\n";
  ++$TNUM; print "ok $TNUM # skip $reason\n";
  ++$TNUM; print "ok $TNUM # skip $reason\n";
}

# Force Data::Dumper::Dump to use perl. We test Dumpxs explicitly by calling
# it direct. Out here it lets us knobble the next if to test that the perl
# only tests do work (and count correctly)
$Data::Dumper::Useperl = 1;
if (defined &Data::Dumper::Dumpxs) {
  print "### XS extension loaded, will run XS tests\n";
  $TMAX = 438; $XS = 1;
}
else {
  print "### XS extensions not loaded, will NOT run XS tests\n";
  $TMAX = 219; $XS = 0;
}

print "1..$TMAX\n";

############# 310
## Perl code was using /...$/ and hence missing the \n.
  $WANT = <<'EOT';
my $VAR1 = '42
';
EOT

  # Can't pad with # as the output has an embedded newline.
  local $Data::Dumper::Pad = "my ";
  TEST q(Data::Dumper->Dump(["42\n"])), "number with trailing newline";
  TEST q(Data::Dumper->Dumpxs(["42\n"])), "XS number with trailing newline"
	if $XS;
