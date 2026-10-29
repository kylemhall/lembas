package Lembas::Controller::Users;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Lembas::Error;

# No parameters: nothing for openapi->valid_input to refuse
sub me ($c) {
    my $user = $c->stash('user');
    return $c->render( openapi => { map { $_ => $user->{$_} } qw(id email name is_admin) } );
}

sub admin_list ($c) {
    $c->require_admin or return;
    return $c->render( openapi => { users => $c->users->list } );
}

sub admin_update ($self) {
    my $c = $self->openapi->valid_input or return;
    $c->require_admin                   or return;
    my $id = $c->validation->output->{id};
    return $c->render_error(
        Lembas::Error->new( code => 'own_account', message => 'Admins cannot change their own account', status => 400 )
    ) if $id == $c->stash('user')->{id};
    return $c->render_error( Lembas::Error->new( code => 'not_found', message => 'No such user', status => 404 ) )
        unless $c->users->find($id);

    $c->users->set_active( $id, $c->req->json->{is_active} );
    return $c->render( openapi => $c->users->find($id) );
}

1;

=head1 NAME

Lembas::Controller::Users - The users, in the REST API

=head2 me

C<GET /api/v1/me>: the user of the request.

=head2 admin_list

C<GET /api/v1/admin/users>

=head2 admin_update

C<PATCH /api/v1/admin/users/{id}>

=cut
