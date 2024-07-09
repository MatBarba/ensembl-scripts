#!/usr/bin/env perl
=head1 LICENSE

See the NOTICE file distributed with this work for additional information
regarding copyright ownership.

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

use JSON;
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

my $db_map = load_external_db_map();
my @data = prepare_data($core_db);

$logger->debug("Print JSON");
print_json(\@data);

###############################################################################

sub prepare_data {
  my ($dba, $db_map) = @_;

  $logger->debug("Prepare data");
  my $genes = prepare_genes($dba, $db_map);
  my ($transcripts, $translations) = prepare_transcripts($dba, $db_map);
  $dba->dbc()->disconnect_if_idle();

  return (@$genes, @$transcripts, @$translations);
}

sub prepare_genes {
  my ($dba, $db_map) = @_;

  $logger->debug("Load genes");
  my $ga = $dba->get_adaptor('Gene');

  my @genes;
  for my $gene (@{$ga->fetch_all()}) {
    # Basic metadata
    my %feat = (
      id => $gene->stable_id,
      object_type => "gene",
    );
    $feat{version} = $gene->version if $gene->version;

    # Gene specific metadata
    my $syns = get_synonyms($gene);
    $feat{synonyms} = $syns if $syns and @$syns;
    $feat{is_pseudogene} = JSON::true if $gene->biotype eq 'pseudogene';
    $feat{description} = $gene->description if $gene->description;

    # Xrefs (if any)
    my $xrefs = get_xrefs($gene, $db_map);
    $feat{xrefs} = $xrefs if $xrefs and @$xrefs;

    push @genes, \%feat;
  }
  @genes = sort { $a->{id} cmp $b->{id} } @genes;
  return \@genes;
}

sub prepare_transcripts {
  my ($dba, $db_map) = @_;

  $logger->debug("Load transcripts and translations");
  my $ta = $dba->get_adaptor('Transcript');

  my @transcripts;
  my @translations;
  for my $transcript (@{$ta->fetch_all()}) {
    # Prepare transcript
    my %tr = (
      id => $transcript->stable_id,
      object_type => "transcript",
    );
    $tr{version} = $transcript->version if $transcript->version;
    $tr{description} = $transcript->description if $transcript->description;
    my $tr_xrefs = get_xrefs($transcript, $db_map);
    $tr{xrefs} = $tr_xrefs if @$tr_xrefs;
    push @transcripts, \%tr;

    # Prepare translation if any
    my $translation = $transcript->translation();
    next if not $translation;
    my %tl = (
      id => $translation->stable_id,
      object_type => "translation",
    );
    $tl{version} = $translation->version if $translation->version;
    my $tl_xrefs = get_xrefs($translation, $db_map);
    $tl{xrefs} = $tl_xrefs if @$tl_xrefs;
    push @translations, \%tl;
  }
  @transcripts = sort { $a->{id} cmp $b->{id} } @transcripts;
  @translations = sort { $a->{id} cmp $b->{id} } @translations;
  return \@transcripts, \@translations;

}

sub get_synonyms {
  my ($gene) = @_;

  my $disp = $gene->display_xref();
  return if not $disp;

  my $name = $disp->display_id;
  my @syns;
  push @syns, { synonym => $name, default => JSON::true } if $name;

  for my $syn (@{ $disp->get_all_synonyms() }) {
    push @syns, $syn;
  }

  return \@syns;
}

sub get_xrefs {
  my ($feature, $db_map) = @_;

  my $entries = $feature->get_all_DBEntries();

  my @xrefs = ();
  my %found_entries;
  ENTRY: for my $entry (@$entries) {
    push @xrefs, create_xref($entry);
    $found_entries{$entry->dbID} = 1;
  }

  # Check that the display_xref is among the xref,
  # add it to the xref otherwise
  if ($feature->can('display_xref')) {
    my $display_entry = $feature->display_xref;
    if ($display_entry and not $found_entries{$display_entry->dbID}) {
      push @xrefs, create_xref($display_entry, $db_map);
    }
  }

  return \@xrefs;
}

sub create_xref {
  my ($entry, $db_map) = @_;

  my $dbname = $entry->dbname;
  my $id = $entry->display_id;
  
  # Replace dbname from external_db map
  if ($db_map and $db_map->{$dbname}) {
    $dbname = $db_map->{$dbname};
  }

  my $xref = { dbname => $dbname, id => $id };
  $xref->{description} = $entry->description if ($entry->description);
  $xref->{info_type} = $entry->info_type if ($entry->info_type and $entry->info_type ne 'NONE');
  $xref->{info_text} = $entry->info_text if ($entry->info_text);
  return $xref;
}

sub load_external_db_map {
  my ($map_path) = @_;
  $logger->debug("Check map load");
  
  my %map;
  if ($map_path) {
    $logger->debug("Load map file");
    open my $mapfh, "<", $map_path or die "$!";
    while (my $line = readline $mapfh) {
      chomp $line;
      next if $line =~ /^\*$/ or $line =~ /^#/;
      # We use the mapping in reverse order because we dump
      my ($to, $from) = split("\t", $line);
      $map{$from} = $to;
    }
    close $mapfh;
  }
  return \%map;
}

sub print_json {
  my ($data) = @_;

  # Print pretty JSON
  my $json = JSON->new;
  print $json->pretty->canonical(1)->encode($data);
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
    Dump gene models from a core database to JSON

    --host <str> : Host to MYSQL server
    --port <int> : Port to MYSQL server
    --user <str> : User to MYSQL server
    --pass <str> : Password to MYSQL server
    --dbname <str> : Database name on the MYSQL server
    
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
    "help",
    "verbose",
    "debug",
  );

  usage("Server params needed") unless $opt{host} and $opt{port} and $opt{user};
  usage() if $opt{help};
  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__
