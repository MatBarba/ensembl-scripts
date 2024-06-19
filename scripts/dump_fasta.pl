#!/usr/bin/env perl
=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

use strict;
use warnings;
use autodie;

use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw( :easy ); 
Log::Log4perl->easy_init($WARN); 
my $logger = get_logger(); 

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::IO::FASTASerializer;

###############################################################################
# MAIN
# Get command line args
my %opt = %{ opt_check() };
my $core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host => $opt{host},
  -user => $opt{user},
  -pass => $opt{pass},
  -port => $opt{port},
  -dbname => $opt{dbname}
);
$logger->debug("Core db loaded");
if ($opt{type} eq "dna") {
  dump_dna($core_db);
} elsif ($opt{type} eq "protein") {
  dump_protein($core_db);
} else {
  usage("Sequence type not supported: $opt{type}");
}

sub dump_dna {
  my ($db) = @_;
  
  my $fh = *STDOUT;
  my $serializer = Bio::EnsEMBL::Utils::IO::FASTASerializer->new($fh);
  my $sa = $db->get_adaptor("slice");

  for my $slice (@{ $sa->fetch_all('toplevel') }) {
    $serializer->print_Seq($slice);
  }
  close $fh;
}

sub dump_protein {
  my ($db) = @_;
  
  my $fh = *STDOUT;
  my $serializer = Bio::EnsEMBL::Utils::IO::FASTASerializer->new($fh);
  my $sa = $db->get_adaptor("slice");
  my $ta = $db->get_adaptor("transcript");

  for my $slice (@{ $sa->fetch_all('toplevel') }) {
    for my $transcript (@{ $ta->fetch_all_by_Slice($slice) }) {
      my $translation = $transcript->translation();
      next if not $translation;
      my $seq = $transcript->translate();
      $serializer->print_Seq($seq);
    }
  }
  close $fh;
}

###############################################################################
# Parameters and usage
sub usage {
  my $error = shift;
  my $help = '';
  if ($error) {
    $help = "[ $error ]\n";
  }
  $help .= <<'EOF';
    Dump sequences from a core database to a FASTA file

    --host <str> : Host to MYSQL server
    --port <int> : Port to MYSQL server
    --user <str> : User to MYSQL server
    --pass <str> : Password to MYSQL server
    --dbname <str> : Database name on the MYSQL server

    --type <str> : Type of sequence to dump (dna, protein)
    
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
    "host=s",
    "port=s",
    "user=s",
    "pass=s",
    "dbname=s",
    "type=s",
    "help",
    "verbose",
    "debug",
  );

  usage("Server params needed") unless $opt{host} and $opt{port} and $opt{user};
  usage("Type of sequence needed") unless $opt{type};
  usage() if $opt{help};
  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__