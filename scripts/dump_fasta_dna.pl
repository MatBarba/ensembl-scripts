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

  'dump_level'            => 'toplevel', # Alternative: seqlevel
  'dump_cs_version'       => "",  # Version of coord_system, only if dump_level is a name
  'include_non_reference' => 1,
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
my $header_function = sub {
  my $slice = shift;
  return $slice->seq_region_name;
};
my $serializer = Bio::EnsEMBL::Utils::IO::FASTASerializer->new(
  $fh,
  $header_function,
  $opt{chunk_factor},
  $opt{line_width},
);
my $sa = $core_db->get_adaptor("slice");

$logger->debug("Print sequences");
my $slices = $sa->fetch_all($opt{dump_level}, $opt{dump_cs_version}, $opt{include_non_reference});
foreach my $slice (sort { $b->length <=> $a->length } @$slices) {
  $serializer->print_Seq($slice);
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
    Dump DNA sequences from a core database to a FASTA file

    --host <str> : Host to MYSQL server
    --port <int> : Port to MYSQL server
    --user <str> : User to MYSQL server
    --pass <str> : Password to MYSQL server
    --dbname <str> : Database name on the MYSQL server

    Optional:
    chunk_factor <int> : (default: $default{chunk_factor})
    line_width <int> :  (default: $default{line_width})
    dump_level <str> : Level of coord system to dump: toplevel or seqlevel (default: $default{dump_level})
    dump_cs_version <str> : Version of coord_system if a name is provided for the dump_level (default: $default{dump_cs_version})
    include_non_reference : Also include non-reference sequences (default: $default{include_non_reference})
    
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
    "chunk_factor=s",
    "line_width=s",
    "dump_level=s",
    "dump_cs_version=s",
    "include_non_reference",
    "help",
    "verbose",
    "debug",
  );

  usage("Server params needed") unless $opt{host} and $opt{port} and $opt{user};
  usage() if $opt{help};

  # Defaults
  $opt{chunk_factor} //= $default{chunk_factor};
  $opt{line_width} //= $default{line_width};
  $opt{dump_level} //= $default{dump_level};
  $opt{dump_cs_version} //= $default{dump_cs_version};
  $opt{include_non_reference} //= $default{include_non_reference};

  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__