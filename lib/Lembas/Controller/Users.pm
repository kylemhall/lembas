package Lembas::Controller::Users;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# No parameters: nothing for openapi->valid_input to refuse
sub me ($c) {
    my $user = $c->stash('user');
    return $c->render( openapi => { map { $_ => $user->{$_} } qw(id email name is_admin) } );
}

1;

=head1 NAME

Lembas::Controller::Users - The users, in the REST API

=head2 me

C<GET /api/v1/me>: the user of the request.

=cut
