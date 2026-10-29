package Lembas::Error;
use Mojo::Base -base, -signatures;

use Scalar::Util qw(blessed);

has [qw(code message status detail)];

sub throw ( $class, %fields ) { die $class->new(%fields) }

sub caught ( $class, $error ) { return blessed($error) && $error->isa($class) }

1;

=head1 NAME

Lembas::Error - An error the user can be told about

=head1 SYNOPSIS

  Lembas::Error->throw( code => 'ending_taken', message => 'This ending is taken', status => 409 );

  $c->render_error($@) if Lembas::Error->caught($@);

=head1 DESCRIPTION

Thrown by the models for anything the caller can show: C<code> is stable, C<message> is for people, C<status> is the
HTTP status that fits, C<detail> is for the logs only.

=head2 throw

Dies with a new error built from the given attributes.

=head2 caught

Whether the given exception is a Lembas::Error.

=cut
