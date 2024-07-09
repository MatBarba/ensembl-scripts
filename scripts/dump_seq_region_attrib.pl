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

use JSON;
use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw( :easy ); 
Log::Log4perl->easy_init($WARN); 
my $logger = get_logger(); 

use Bio::EnsEMBL::DBSQL::DBAdaptor;

my $allowed_transcript_attribs = {
  _rna_edit     => "sequence_alteration",
  Frameshift    => "frameshift",
  _transl_start => "coding_start",
  _transl_end   => "coding_end",
};
my $allowed_translation_attribs = {
  amino_acid_sub  => "sequence_alteration",
  initial_met     => "sequence_alteration",
  _selenocysteine => "selenocysteine",
};

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
my $attribs = prepare_data($core_db);
my $json = JSON->new;
print $json->pretty->canonical(1)->encode($attribs);

###############################################################################
sub prepare_data {
  my ($dba) = @_;

  # Get genes
  my @features;
  my $ta = $dba->get_adaptor('Transcript');
  my $pa = $dba->get_adaptor('Translation');
  
  my @seq_attribs;

  # Get transcript attribs
  my $type = 'transcript';
  $logger->warn("Load transcripts attribs...");
  foreach my $transcript (@{$ta->fetch_all()}) {
    my $attribs = get_transcript_seq_attribs($transcript);
    push @seq_attribs, @$attribs;
  }
  
  # Get translation attribs
  $type = 'translation';
  $logger->warn("Load translations attribs...");
  foreach my $translation (@{$pa->fetch_all()}) {
    my $attribs = get_translation_seq_attribs($translation);
    push @seq_attribs, @$attribs;
  }

  $dba->dbc()->disconnect_if_idle();

  # Sort for easier file comparison
  @seq_attribs = sort { $a->{object_id} cmp $b->{object_id} } @seq_attribs;

  return \@seq_attribs;
}


sub get_transcript_seq_attribs {
  my ($transcript) = @_;

  my $allowed_attribs = $allowed_transcript_attribs;

  # Get all attributes at once
  my $attribs = $transcript->get_all_Attributes();

  my @selected_attribs;
  my $object_type = 'transcript';
  for my $attrib (@$attribs) {
    my $code = $attrib->code;
    if ($allowed_attribs->{$code}) {
      $code = $allowed_attribs->{$code};
      my %attrib = (
        object_type => $object_type,
        object_id   => $transcript->stable_id,
        seq_attrib_type => $code,
      );
      my $attrib_values;

      # Get attrib specific values
      if ($code eq 'sequence_alteration') {
        $attrib_values = format_edit($attrib);
      } elsif ($code eq 'coding_start' or
               $code eq 'coding_end') {
        $attrib_values = format_position($attrib);
      } elsif ($code eq 'frameshift') {
        $attrib_values = format_frameshift($attrib);
      }
      die("Could not get attrib values for $code, ".$transcript->stable_id) if not $attrib_values;

      # Merge attrib values
      %attrib = (%attrib, %$attrib_values);
      push @selected_attribs, \%attrib;
    }
  }
  return \@selected_attribs;
}

sub get_translation_seq_attribs {
  my ($translation) = @_;

  my $allowed_attribs = $allowed_translation_attribs;

  # Get all attributes at once
  my $attribs = $translation->get_all_Attributes();

  my @selected_attribs;
  my $object_type = 'translation';
  for my $attrib (@$attribs) {
    my $code = $attrib->code;
    if ($allowed_attribs->{$code}) {
      $code = $allowed_attribs->{$code};
      my %attrib = (
        object_type => $object_type,
        object_id   => $translation->stable_id,
        seq_attrib_type => $code,
      );
      my $attrib_values;

      # Get attrib specific values
      if ($code eq 'sequence_alteration') {
        $attrib_values = format_edit($attrib);
      } elsif ($code eq 'selenocysteine') {
        $attrib_values = format_position($attrib);
      }
      die("Could not get attrib values for $code, ".$translation->stable_id) if not $attrib_values;

      # Merge attrib values
      %attrib = (%attrib, %$attrib_values);
      push @selected_attribs, \%attrib;
    }
  }
  return \@selected_attribs;
}

sub format_edit {
  my ($attrib) = @_;

  my ($start, $end, $seq) = split / /, $attrib->value;
  ($start, $end) = ensembl_to_interbase($start, $end);

  my %values = (
    start => int($start),
    end => int($end),
    sequence => $seq,
  );
  return \%values;
}

sub ensembl_to_interbase {
  my ($start, $end) = @_;

  # The only difference between Ensembl current system (1-based) and
  # an interbase system (0-based) is that Ensembl start is +1
  # The result is more legible
  $start--;

  return ($start, $end);
}

sub format_position {
  my ($attrib) = @_;

  my %values = (
    position => int($attrib->value),
  );

  return \%values;
}

sub format_frameshift {
  my ($attrib) = @_;

  my %values = (
    intron_number => int($attrib->value),
  );

  return \%values;
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
    Dump gene seq_region attribs for transcripts and translations from a core database.

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
