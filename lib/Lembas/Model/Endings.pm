package Lembas::Model::Endings;
use Mojo::Base -base, -signatures;

use Crypt::PRNG qw(random_string_from);

# The first path segment of every route and static directory: an ending equal to one could never be reached
use constant RESERVED => [qw(admin api auth css favicon.ico health js links ready robots.txt vendor)];
use constant PATTERN  => qr/\A[A-Za-z0-9_-]{1,64}\z/;
use constant ALPHABET => join q{}, 'A' .. 'Z', 'a' .. 'z', 0 .. 9;

my %RESERVED = map { $_ => 1 } @{ RESERVED() };

has generator => sub { \&random_string_from };

sub is_valid ( $self, $ending ) { return $ending =~ PATTERN }

sub is_reserved ( $self, $ending ) { return exists $RESERVED{ lc $ending } }

sub random ( $self, $length ) { return $self->generator->( ALPHABET, $length ) }

1;

=head1 NAME

Lembas::Model::Endings - The endings of the short links

=head1 SYNOPSIS

  my $endings = Lembas::Model::Endings->new;
  my $ending  = $endings->random(6);

=head1 DESCRIPTION

Endings are 1 to 64 letters, digits, C<-> and C<_>. They are case sensitive, but a reserved word is reserved whatever
its case.

=head2 is_valid

Whether the ending has the allowed characters and length.

=head2 is_reserved

Whether the ending is the first path segment of a page of the application.

=head2 random

A random ending of the given length, from letters and digits (C<generator> is C<Crypt::PRNG::random_string_from>).

=cut
