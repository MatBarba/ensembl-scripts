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

my %default = (
  'chunk_factor'          => 1000,
  'line_width'            => 80,

  'only_canonical' => 0,
  'skip_stop_codons' => 0,
);

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

my $fh = *STDOUT;
my $serializer = Bio::EnsEMBL::Utils::IO::FASTASerializer->new($fh);
my $sa = $core_db->get_adaptor("slice");
my $ta = $core_db->get_adaptor("transcript");

for my $slice (@{ $sa->fetch_all('toplevel') }) {
  $logger->debug("Get peptides from " . $slice->seq_region_name());
  for my $transcript (@{ $ta->fetch_all_by_Slice($slice) }) {
    next if $opt{only_canonical} and not $transcript->is_canonical;
    my $seq = $transcript->translate();
    next if not $seq;
    # Standardize ID
    $seq->display_id($transcript->translation->stable_id);

    # Check sequence for stop codons
    if ($opt{skip_stop_codons} and $seq->seq() =~ /\*/) {
      my $seq_id = $seq->stable_id;
      $logger->debug("Skip $seq_id with stop codons");
      next;
    }
    $serializer->print_Seq($seq);
  }
}
close $fh;

###############################################################################
# Parameters and usage
sub usage {
  my $error = shift;
  my $help = '';
  if ($error) {
    $help = "[ $error ]\n";
  }
  $help .= <<"EOF";
    Dump sequences from a core database to a FASTA file

    --host <str> : Host to MYSQL server
    --port <int> : Port to MYSQL server
    --user <str> : User to MYSQL server
    --pass <str> : Password to MYSQL server
    --dbname <str> : Database name on the MYSQL server

    Optional:
    chunk_factor <int> : (default: $default{chunk_factor})
    line_width <int> :  (default: $default{line_width})
    only_canonical : Only export canonical translations (default: $default{only_canonical})
    skip_stop_codons : Exclude proteins with stop codons within (default: $default{skip_stop_codons})
    
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
    "chunk_factor=s",
    "line_width=s",
    "only_canonical",
    "skip_stop_codons",
    "help",
    "verbose",
    "debug",
  );

  usage("Server params needed") unless $opt{host} and $opt{port} and $opt{user};
  usage() if $opt{help};

  # Defaults
  $opt{chunk_factor} //= $default{chunk_factor};
  $opt{line_width} //= $default{line_width};
  $opt{only_canonical} //= $default{only_canonical};
  $opt{skip_stop_codons} //= $default{skip_stop_codon};

  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__