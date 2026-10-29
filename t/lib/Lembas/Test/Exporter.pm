package Lembas::Test::Exporter;
use Mojo::Base -base, -signatures;

use Future;
use Mojo::File               qw(path);
use OpenTelemetry::Constants qw(EXPORT_RESULT_SUCCESS);

has exported => sub { [] };
has result   => EXPORT_RESULT_SUCCESS;
has fails    => 0;
has 'file';

sub DOES ( $self, $role ) { return $role eq 'OpenTelemetry::Exporter' || $self->SUPER::DOES($role) }

# In a child process the items cannot come back: the count is written to "file", when there is one
sub export ( $self, $batch, @ ) {
    die "The exporter fails\n" if $self->fails;
    push @{ $self->exported }, @$batch;
    path( $self->file )->spew( scalar @$batch ) if $self->file;
    return $self->result;
}

sub force_flush ( $self, @ ) { return Future->done(EXPORT_RESULT_SUCCESS) }

## no critic (Subroutines::ProhibitBuiltinHomonyms)
sub shutdown ( $self, @ ) { return Future->done(EXPORT_RESULT_SUCCESS) }
## use critic

1;

=head1 NAME

Lembas::Test::Exporter - An OpenTelemetry exporter that keeps what it is given

=head1 SYNOPSIS

  my $exporter = Lembas::Test::Exporter->new;
  ...
  my @spans = @{ $exporter->exported };

=head1 DESCRIPTION

C<result> is what C<export> returns, C<fails> makes it die, C<file> receives the number of items exported.

=cut
