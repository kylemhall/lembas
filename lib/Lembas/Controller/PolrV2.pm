package Lembas::Controller::PolrV2;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Lembas::Error;

use constant MISSING => 'Invalid or missing parameters.';

sub shorten ($c) {
    my $user = $c->_authenticate or return;
    my $url  = $c->param('url');
    return $c->_error( 400, 'MISSING_PARAMETERS', MISSING ) unless length $url;

    my $ending = $c->param('custom_ending');
    my $link;
    eval {
        ($link) = $c->links->create(
            { long_url => $url, ending => length $ending ? $ending : undef, user_id => $user->{id}, is_api => 1 } );
        1;
    } or do {
        my $error = $@;
        die $error unless Lembas::Error->caught($error);
        return $c->_error( 400, 'CREATION_ERROR', $error->message );
    };
    return $c->_result( shorten => $link->{short_url}, $link->{short_url} );
}

sub lookup ($c) {
    $c->_authenticate or return;
    my $ending = $c->param('url_ending');
    return $c->_error( 400, 'MISSING_PARAMETERS', MISSING ) unless length $ending;
    my $link = $c->links->find_by_ending($ending) or return $c->_error( 404, 'NOT_FOUND', 'Link not found.' );
    return $c->_result(
        lookup => { map { $_ => $link->{$_} } qw(long_url clicks created_at updated_at) },
        $link->{long_url}
    );
}

# The user of the "key" parameter: renders the error of Polr and returns nothing otherwise
sub _authenticate ($c) {
    my $key = $c->param('key');
    unless ( length $key ) {
        $c->_error( 401, 'AUTH_ERROR', 'Authentication token required.' );
        return;
    }
    my $user_id = $c->api_keys->authenticate($key);
    unless ($user_id) {
        $c->_error( 401, 'AUTH_ERROR', 'Authentication token invalid.' );
        return;
    }
    return $c->users->find($user_id);
}

sub _result ( $c, $action, $result, $text ) {
    return $c->_render(
        200,
        $c->_wants_json ? ( json => { action => $action, result => $result } ) : ( text => $text )
    );
}

sub _error ( $c, $status, $code, $message ) {
    return $c->_render(
        $status,
        $c->_wants_json
        ? ( json => { status_code => $status, error_code => $code, error => $message } )
        : ( text => "$status $message" )
    );
}

# Plain text unless response_type=json, as in Polr
sub _wants_json ($c) { return ( $c->param('response_type') // q{} ) eq 'json' }

sub _render ( $c, $status, $type, $body ) {
    my $headers = $c->res->headers;
    $headers->header( 'Access-Control-Allow-Origin' => '*' );
    $headers->header( Link                          => '</api/v1>; rel="successor-version"' );
    return $c->render( $type => $body, status => $status, $type eq 'text' ? ( format => 'txt' ) : () );
}

1;

=head1 NAME

Lembas::Controller::PolrV2 - The API of Polr, for the scripts written for it

=head1 DESCRIPTION

C</api/v2/action/shorten> and C</api/v2/action/lookup>, with GET or POST, as Polr 2 answers them: the API key in the
C<key> parameter, plain text unless C<response_type=json>. Secret links (C<is_secret>, C<url_key>) do not exist in
Lembas: such links are public. New code uses C</api/v1>.

=head2 shorten

The short URL of C<url>, with C<custom_ending> when given.

=head2 lookup

The long URL of C<url_ending>; in JSON with its clicks and dates.

=cut
