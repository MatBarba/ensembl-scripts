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

use File::Spec::Functions qw(catdir catfile);
use File::Path qw(mkpath);
use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw( :easy ); 
Log::Log4perl->easy_init($WARN); 
my $logger = get_logger(); 

use Bio::EnsEMBL::DBSQL::DBAdaptor;

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
extract_agp($core_db, $opt{output_dir});

###############################################################################
sub extract_agp {
  my ($dba, $output_dir) = @_;
  
  my $species = get_species($dba);

  my $gap_type = 'scaffold';
  my $linkage  = 'yes';
  my $evidence = 'paired-ends';
  
  my $ama = $dba->get_adaptor('AssemblyMapper');
  my $csa = $dba->get_adaptor('CoordSystem');
  my $sa  = $dba->get_adaptor('Slice');

  my @coord_maps = get_coord_maps($dba, $species);

  # Don't generate AGP if there is no mapping (i.e. only one coord_system)
  return if @coord_maps == 0;

  mkpath($output_dir);
  my %agp_files;
  foreach my $pair (@coord_maps) {
    my $first_level_cs = $csa->fetch_by_dbID($pair->[0]);
    my $second_level_cs = $csa->fetch_by_dbID($pair->[1]);
  
    my $mapper = $ama->fetch_by_CoordSystems($first_level_cs, $second_level_cs);
    my $non_ref = 1;
    my $slices = $sa->fetch_all($first_level_cs->name, $first_level_cs->version, $non_ref);

    $logger->debug(sprintf("Coords: %s vs %s : %d slices", $first_level_cs->name, $second_level_cs->name, scalar(@$slices)));

    my $map_name = $first_level_cs->name() . "-" . $second_level_cs->name();
    my $agp_file = catfile($output_dir, $species . '_assembly_' . $map_name . '.agp');
    $logger->info("Write file $agp_file");
    $agp_files{$map_name} = $agp_file;
    open(my $out_fh, '>', $agp_file);
    foreach my $slice (sort {$a->seq_region_name cmp $b->seq_region_name} @$slices) {
      my @seq_level_coords =
        $mapper->map(
          $slice->seq_region_name,
          $slice->start,
          $slice->end,
          $slice->strand,
          $first_level_cs
        );
      
      my $asm_start = 1;
      my $cmp_count = 0;
      
      foreach my $seq_level_coord (@seq_level_coords) {
        my $length = $seq_level_coord->end - $seq_level_coord->start + 1;
        my @line = ($slice->seq_region_name);
        
        if ($seq_level_coord->isa('Bio::EnsEMBL::Mapper::Coordinate')) {
          my $seq_level_name = $ama->seq_ids_to_regions([$seq_level_coord->id]);
          my $orientation = ($seq_level_coord->strand eq -1) ? '-' : '+';
          
          push @line, (
            $asm_start,
            $asm_start + $length - 1,
            ++$cmp_count,
            'W',
            $$seq_level_name[0],
            $seq_level_coord->start,
            $seq_level_coord->end,
            $orientation
          );
          
        } elsif ($seq_level_coord->isa('Bio::EnsEMBL::Mapper::Gap')) {          
          push @line, (
            $seq_level_coord->start,
            $seq_level_coord->end,
            ++$cmp_count,
            'N',
            $length,
            $gap_type,
            $linkage,
            $evidence
          );
          
        }
        print $out_fh join("\t", @line)."\n";
        
        $asm_start += $length;
      }
    }
    close($out_fh);
  }
  
  return \%agp_files;
}

sub get_species {
  my ($dba) = @_;

  my $ma = $dba->get_adaptor('MetaContainer');
  return $ma->get_production_name();
}

sub get_coord_maps {
  my ($dba, $species) = @_;

  my $pairs_sql = "
    SELECT sa.coord_system_id, sc.coord_system_id
    FROM assembly a
      LEFT JOIN seq_region sa ON a.asm_seq_region_id = sa.seq_region_id
      LEFT JOIN seq_region sc ON a.cmp_seq_region_id = sc.seq_region_id
      LEFT JOIN coord_system ca ON sa.coord_system_id = ca.coord_system_id
      LEFT JOIN coord_system cc ON sc.coord_system_id = cc.coord_system_id
      LEFT JOIN meta m ON ca.species_id = m.species_id
    WHERE ca.attrib LIKE '\%default_version%'
      AND cc.attrib LIKE '\%default_version%'
      AND m.meta_key = 'species.production_name'
      AND m.meta_value = '$species'
    GROUP BY sa.coord_system_id, sc.coord_system_id;
  ";
  
  my $dbh = $dba->dbc->db_handle();

  my $sth = $dbh->prepare($pairs_sql);
  $sth->execute();

  my @pairs;
  while (my @pair = $sth->fetchrow_array()) {
    push @pairs, \@pair;
  }

  return @pairs;
}

1;


###############################################################################
# Parameters and usage
sub usage {
  my $error = shift;
  my $help = '';
  if ($error) {
    $help = "[ $error ]\n";
  }
  $help .= <<'EOF';
    Dump gene models from a core database to a GFF3 file

    --host <str> : Host to MYSQL server
    --port <int> : Port to MYSQL server
    --user <str> : User to MYSQL server
    --pass <str> : Password to MYSQL server
    --dbname <str> : Database name on the MYSQL server
    --output_dir <apth> : Path where AGP files are written
    
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
    "output_dir=s",
    "help",
    "verbose",
    "debug",
  );

  usage("Server params needed") unless $opt{host} and $opt{port} and $opt{user};
  usage("Output dir needed") unless $opt{output_dir};
  usage() if $opt{help};
  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__
