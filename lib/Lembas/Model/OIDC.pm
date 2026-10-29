package Lembas::Model::OIDC;
use Mojo::Base -base, -signatures;

use Crypt::JWT   qw(decode_jwt);
use Crypt::PRNG  qw(random_bytes);
use Digest::SHA  qw(sha256);
use MIME::Base64 qw(encode_base64url);
use Mojo::URL;
use Mojo::UserAgent;
use Lembas::Error;

# Google serves its discovery document and its keys with several hours of max-age
use constant CACHE_SECONDS => 3600;

# An unknown key id may come from anybody: the keys are fetched again once a minute at most
use constant REFRESH_SECONDS => 60;

use constant UNVERIFIED => 'The sign-in could not be verified, try again';

has [qw(issuer client_id client_secret redirect_url allowed_domain)];
has ua  => sub { Mojo::UserAgent->new( connect_timeout => 5, request_timeout => 10 ) };
has now => sub { \&CORE::time };

# Fetched on the first sign-in, not at startup: the application starts without the sign-in service
sub discovery ($self) {
    my $now = $self->now->();
    return $self->{discovery} if $self->{discovery} && $now - $self->{discovery_at} < CACHE_SECONDS;
    $self->{discovery}    = $self->_get_json( $self->issuer . '/.well-known/openid-configuration' );
    $self->{discovery_at} = $now;
    return $self->{discovery};
}

sub jwks ( $self, $refresh ) {
    my $age = $self->{jwks} ? $self->now->() - $self->{jwks_at} : CACHE_SECONDS;
    return $self->{jwks} if $age < ( $refresh ? REFRESH_SECONDS : CACHE_SECONDS );
    $self->{jwks}    = $self->_get_json( $self->discovery->{jwks_uri} );
    $self->{jwks_at} = $self->now->();
    return $self->{jwks};
}

# The URL of the sign-in page, and the secrets to keep in the session until the user comes back
sub authorization_request ($self) {
    my %secret = map { $_ => encode_base64url( random_bytes(32) ) } qw(state nonce code_verifier);
    my $url    = Mojo::URL->new( $self->discovery->{authorization_endpoint} )->query(
        response_type         => 'code',
        client_id             => $self->client_id,
        redirect_uri          => $self->redirect_url,
        scope                 => 'openid email profile',
        state                 => $secret{state},
        nonce                 => $secret{nonce},
        code_challenge        => encode_base64url( sha256( $secret{code_verifier} ) ),
        code_challenge_method => 'S256',
        hd                    => $self->allowed_domain,
        prompt                => 'select_account',
    );
    return { %secret, url => $url->to_string };
}

sub exchange_code ( $self, $code, $code_verifier ) {
    my $tx = $self->ua->post(
        $self->discovery->{token_endpoint} => form => {
            grant_type    => 'authorization_code',
            code          => $code,
            redirect_uri  => $self->redirect_url,
            client_id     => $self->client_id,
            client_secret => $self->client_secret,
            code_verifier => $code_verifier,
        }
    );
    my $error    = $tx->error;
    my $id_token = $error ? undef : $tx->res->json('/id_token');
    return $id_token if defined $id_token;
    Lembas::Error->throw(
        code    => 'oidc_exchange_failed',
        message => 'The sign-in could not be completed, try again',
        status  => 502,
        detail  => $error ? $error->{message} : 'The response has no id_token',
    );
}

sub verify_id_token ( $self, $id_token, $nonce ) {
    my $claims = $self->_decode_with_refresh($id_token);
    Lembas::Error->throw( code => 'oidc_nonce_mismatch', message => UNVERIFIED, status => 401 )
        unless ( $claims->{nonce} // q{} ) eq $nonce;
    Lembas::Error->throw(
        code    => 'oidc_email_unverified',
        message => 'The email address of this Google account is not verified',
        status  => 403
    ) unless $claims->{email_verified};

    # hd is the Workspace domain: personal Google accounts have none, and the email must match it too
    my $domain = $self->allowed_domain;
    my $email  = lc( $claims->{email} // q{} );
    Lembas::Error->throw(
        code    => 'oidc_wrong_domain',
        message => "Only $domain Google accounts can sign in",
        status  => 403
    ) unless ( $claims->{hd} // q{} ) eq $domain && $email =~ /\@\Q$domain\E\z/;

    return { sub => $claims->{sub}, email => $email, name => $claims->{name} // q{} };
}

sub _get_json ( $self, $url ) {
    my $tx    = $self->ua->get($url);
    my $error = $tx->error or return $tx->res->json;
    Lembas::Error->throw(
        code    => 'oidc_unavailable',
        message => 'The sign-in service cannot be reached, try again later',
        status  => 503,
        detail  => "$url: $error->{message}",
    );
}

sub _decode_with_refresh ( $self, $id_token ) {
    my $keys = $self->jwks(0);
    my $claims;
    return $claims if eval { $claims = $self->_decode( $id_token, $keys ); 1 };
    my $error = $@;

    # Google rotates its keys: a token signed with a key the cache does not have yet is worth another look
    if ( $error =~ /kid_keys lookup failed/ ) {
        my $fresh_keys = $self->jwks(1);
        return $claims if eval { $claims = $self->_decode( $id_token, $fresh_keys ); 1 };
        $error = $@;
    }
    Lembas::Error->throw(
        code    => $error =~ /exp claim check failed/ ? 'oidc_expired' : 'oidc_bad_token',
        message => UNVERIFIED,
        status  => 401,
        detail  => $error,
    );
}

sub _decode ( $self, $id_token, $keys ) {
    my $issuer = Mojo::URL->new( $self->issuer );
    my ( $scheme, $host ) = ( $issuer->scheme, $issuer->host_port );
    return decode_jwt(
        token        => $id_token,
        kid_keys     => $keys,
        accepted_alg => ['RS256'],

        # Google names itself with or without the scheme
        verify_iss => qr{\A(?:\Q$scheme\E://)?\Q$host\E\z},
        verify_aud => $self->client_id,
        verify_exp => 1,
        leeway     => 60,
    );
}

1;

=head1 NAME

Lembas::Model::OIDC - Sign in with Google, with OpenID Connect

=head1 SYNOPSIS

  my $request  = $oidc->authorization_request;    # redirect to $request->{url}, keep the rest
  ...
  my $id_token = $oidc->exchange_code( $code, $request->{code_verifier} );
  my $claims   = $oidc->verify_id_token( $id_token, $request->{nonce} );

=head1 DESCRIPTION

The authorization code flow with PKCE. The ID token is verified with the keys of the provider (signature, issuer,
audience, expiry), then its nonce, and the account must have a verified email address in C<allowed_domain>, its
Workspace domain. Every failure is a L<Lembas::Error>.

=head2 discovery

The discovery document of the issuer, cached for an hour.

=head2 jwks

The keys of the provider, cached for an hour; when C<refresh> is true they are fetched again unless they are less than
a minute old.

=head2 authorization_request

The C<url> of the sign-in page, with the C<state>, C<nonce> and C<code_verifier> to keep until the callback.

=head2 exchange_code

The ID token for the code of the callback.

=head2 verify_id_token

The C<sub>, C<email> (in lower case) and C<name> of a valid ID token for this nonce.

=cut
