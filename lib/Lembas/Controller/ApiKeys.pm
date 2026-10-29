package Lembas::Controller::ApiKeys;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Lembas::Error;

# No parameters: nothing for openapi->valid_input to refuse
sub list ($c) { return $c->render( openapi => { api_keys => $c->api_keys->list( $c->stash('user')->{id} ) } ) }

sub create ($self) {
    my $c = $self->openapi->valid_input or return;
    return $c->render(
        openapi => $c->api_keys->create( $c->stash('user')->{id}, $c->req->json->{label} ),
        status  => 201
    );
}

sub revoke ($self) {
    my $c = $self->openapi->valid_input or return;
    return $c->rendered(204) if $c->api_keys->revoke( $c->stash('user')->{id}, $c->validation->output->{id} );
    return $c->render_error( Lembas::Error->new( code => 'not_found', message => 'No such API key', status => 404 ) );
}

1;

=head1 NAME

Lembas::Controller::ApiKeys - The API keys of the user, in the REST API

=head1 DESCRIPTION

Only with the session cookie: an API key cannot make or revoke keys.

=head2 list

C<GET /api/v1/api_keys>

=head2 create

C<POST /api/v1/api_keys>

=head2 revoke

C<DELETE /api/v1/api_keys/{id}>

=cut
