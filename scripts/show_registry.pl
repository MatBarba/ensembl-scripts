#!/usr/bin/env perl
use v5.14.00;
use strict;
use warnings;
use Carp;
use autodie qw(:all);
use Readonly;
use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw( :easy ); 
Log::Log4perl->easy_init($WARN); 
my $logger = get_logger(); 
use Capture::Tiny ':all';

use Bio::EnsEMBL::Registry;
use Try::Tiny;

###############################################################################
# MAIN
# Get command line args
my %opt = %{ opt_check() };

my $registry = 'Bio::EnsEMBL::Registry';

my $reg_path = $opt{registry};
$registry->load_all($reg_path);

my $sps = $registry->get_all_species();

my @lines;
my %report;

my $ens_version = 0;
for my $sp (sort @$sps) {
  my $dbas;
  my %groups;
  $dbas = $registry->get_all_DBAdaptors($sp);
  %groups = map { $_->group => 1 } @$dbas;

  my $stats = "";
  my $db = "";
  my $name = "";
  my ($core) = grep { $_->group eq 'core' } @$dbas;
  my $skip = 0;

  if ($core) {
    try {
      my ($stdout, $stderr) = capture {
        $db = $core->dbc->dbname;

        if ($db =~ /_(\d+)_\d+$/) {
          $ens_version = $1;
        }

        my $genea = $core->get_GeneAdaptor();
        my $tra = $core->get_TranscriptAdaptor();
        my $meta = $registry->get_adaptor($sp, "core", "MetaContainer");
        my ($insdc) = @{ $meta->list_value_by_key("assembly.accession") };
        $stats .= "$insdc\t" if $insdc;

        if ($opt{species}) {
          if ($sp and $sp =~ /$opt{species}/) {
            $skip = 0;
          } else {
            $skip = 1;
          }
        }

        push @lines, "$db\t$sp\t$name\t" . join(", ", sort keys %groups) . "\t$stats" if not $skip;
      };
      $core->dbc->disconnect_if_idle();
      print($stdout);

      print STDERR $stderr if $opt{debug};
    } catch {
      warn("Error: can't use core for $sp: $_");
    };
  }
}

say join("\n", @lines);

###############################################################################
# Parameters and usage
sub usage {
  my $error = shift;
  my $help = '';
  if ($error) {
    $help = "[ $error ]\n";
  }
  $help .= <<'EOF';
    Show metadata for core DBs listed in a registry

    --registry <path> : Ensembl registry

    Optional:
    --species <str>   : production_name from core db
    
    --help            : show this help message
    --verbose         : show detailed progress
    --debug           : show even more information (for debugging purposes)
EOF
  print STDERR "$help\n";
  exit(1);
}

sub opt_check {
  my %opt = ();
  GetOptions(\%opt,
    "registry=s",
    "species=s",
    "help",
    "verbose",
    "debug",
  );

  usage("Registry needed") if not $opt{registry};
  usage()                  if $opt{help};
  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__
