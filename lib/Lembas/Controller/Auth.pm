package Lembas::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Lembas::Error;

# The seconds a user has to sign in at the provider
use constant MAX_AGE => 600;

# Only paths of Lembas: never another site (//example.org is one)
use constant LOCAL_PATH => qr{\A/(?![/\\])};

sub login ($c) {
    return $c->redirect_to('/') if $c->current_user;
    my $request;
    eval { $request = $c->oidc->authorization_request; 1 } or return $c->_failed($@);

    my $return_to = $c->param('return_to') // q{};
    $c->session(
        oidc => {
            state         => $request->{state},
            nonce         => $request->{nonce},
            code_verifier => $request->{code_verifier},
            return_to     => $return_to =~ LOCAL_PATH ? $return_to : '/',
            started_at    => $c->oidc->now->(),
        }
    );
    return $c->redirect_to( $request->{url} );
}

sub callback ($c) {

    # One use only, whatever happens next
    my $pending = delete $c->session->{oidc};

    return $c->_refuse( 400, 'The sign-in was cancelled' ) if defined $c->param('error');
    my ( $state, $code ) = ( $c->param('state'), $c->param('code') );
    return $c->_refuse( 400, 'The sign-in response is incomplete, try again' ) unless defined $state && defined $code;
    return $c->_refuse( 400, 'The sign-in expired, try again' )
        if !$pending || $c->oidc->now->() - $pending->{started_at} > MAX_AGE;
    return $c->_refuse( 400, 'The sign-in does not match, try again' ) unless $state eq $pending->{state};

    my $user;
    eval {
        my $id_token = $c->oidc->exchange_code( $code, $pending->{code_verifier} );
        $user = $c->users->find_or_create_from_claims( $c->oidc->verify_id_token( $id_token, $pending->{nonce} ) );
        1;
    } or return $c->_failed($@);
    return $c->_refuse( 403, 'This account is disabled' ) unless $user->{is_active};

    $c->session( user_id => $user->{id} );
    return $c->redirect_to( $pending->{return_to} );
}

sub logout ($c) {
    return $c->_refuse( 403, 'The page expired, try again' ) if $c->validation->csrf_protect->has_error('csrf_token');
    $c->session( expires => 1 );
    return $c->redirect_to('/');
}

sub _refuse ( $c, $status, $message ) { return $c->render( 'auth/error', status => $status, message => $message ) }

sub _failed ( $c, $error ) {
    die $error unless Lembas::Error->caught($error);
    $c->log->warn( 'Sign-in failed: ' . $error->code . ( defined $error->detail ? ' (' . $error->detail . ')' : q{} ) );
    return $c->_refuse( $error->status, $error->message );
}

1;

=head1 NAME

Lembas::Controller::Auth - Sign in with Google, sign out

=head2 login

C<GET /auth/login>: to the sign-in page of the provider. C<return_to>, a path of Lembas, is where the user goes back.

=head2 callback

C<GET /auth/callback>: where the provider sends the user back. Signs them in, or tells why it cannot.

=head2 logout

C<POST /auth/logout>, with a C<csrf_token>.

=cut
