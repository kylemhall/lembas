package Lembas::Test::OIDC;
use Mojo::Base 'Mojolicious', -signatures;

use Crypt::JWT qw(encode_jwt);
use Crypt::PK::RSA;
use Digest::SHA  qw(sha256);
use MIME::Base64 qw(encode_base64url);
use Mojo::JSON   qw(true);
use Mojo::URL;
use Mojo::UserAgent;

has issuer        => 'http://oidc.invalid';
has client_id     => 'lembas-test';
has client_secret => 'test-client-secret';
has key           => sub { Crypt::PK::RSA->new->generate_key(256) };
has kid           => 'key-1';
has signing_key   => sub ($self) { $self->key };
has header_kid    => sub ($self) { $self->kid };
has claims        => sub { {} };
has fail          => sub { {} };
has pending       => sub { {} };
has requests      => sub { [] };
has ua            => sub { Mojo::UserAgent->new };

# A provider served in this process, on the event loop of its own user agent
sub serve ( $class, %attributes ) {
    my $self = $class->new(%attributes);
    $self->ua->server->app($self);
    $self->issuer( $self->ua->server->url->to_string =~ s{/\z}{}r );
    return $self;
}

sub startup ($self) {
    $self->log->level('fatal');
    my $r = $self->routes;

    $r->get(
        '/.well-known/openid-configuration' => sub ($c) {
            push @{ $self->requests }, 'discovery';
            return $c->render( text => 'down', status => 500 ) if $self->fail->{discovery};
            my $issuer = $self->issuer;
            return $c->render(
                json => {
                    issuer                 => $issuer,
                    authorization_endpoint => "$issuer/authorize",
                    token_endpoint         => "$issuer/token",
                    jwks_uri               => "$issuer/jwks",
                }
            );
        }
    );

    $r->get(
        '/jwks' => sub ($c) {
            push @{ $self->requests }, 'jwks';
            return $c->render( text => 'down', status => 500 ) if $self->fail->{jwks};
            my %jwk =
                ( %{ $self->key->export_key_jwk( 'public', 1 ) }, kid => $self->kid, use => 'sig', alg => 'RS256' );
            return $c->render( json => { keys => [ \%jwk ] } );
        }
    );

    # The user signs in at once: back to the application with a code
    $r->get(
        '/authorize' => sub ($c) {
            my $code = 'code-' . ( 1 + keys %{ $self->pending } );
            $self->pending->{$code} = $c->req->query_params->to_hash;
            return $c->redirect_to(
                Mojo::URL->new( $c->param('redirect_uri') )->query( code => $code, state => $c->param('state') ) );
        }
    );

    $r->post(
        '/token' => sub ($c) {
            push @{ $self->requests }, 'token';
            my $pending = $self->pending->{ $c->param('code') // q{} };
            my $valid =
                  !$self->fail->{token}
                && $pending
                && ( $c->param('client_secret') // q{} ) eq $self->client_secret
                && encode_base64url( sha256( $c->param('code_verifier') // q{} ) ) eq $pending->{code_challenge};
            return $c->render( json => { error        => 'invalid_grant' }, status => 400 ) unless $valid;
            return $c->render( json => { access_token => 'access-token' } ) if $self->fail->{id_token};
            return $c->render(
                json => {
                    access_token => 'access-token',
                    token_type   => 'Bearer',
                    expires_in   => 3600,
                    id_token     => $self->id_token( $pending->{nonce} )
                }
            );
        }
    );
    return;
}

# The claims of Jane Doe, of example.org, with "claims" over them: an undef value removes a claim
sub id_token ( $self, $nonce ) {
    my %claims = (
        iss            => $self->issuer,
        aud            => $self->client_id,
        sub            => 'google-jane',
        email          => 'jane@example.org',
        email_verified => true,
        name           => 'Jane Doe',
        hd             => 'example.org',
        nonce          => $nonce,
        iat            => time,
        exp            => time + 300,
        %{ $self->claims },
    );
    delete @claims{ grep { !defined $claims{$_} } keys %claims };
    return encode_jwt(
        payload       => \%claims,
        key           => $self->signing_key,
        alg           => 'RS256',
        extra_headers => { kid => $self->header_kid }
    );
}

# The keys change, as Google's do
sub rotate_key ($self) {
    $self->key( Crypt::PK::RSA->new->generate_key(256) )->kid('key-2');
    $self->signing_key( $self->key )->header_kid('key-2');
    return $self;
}

1;

=head1 NAME

Lembas::Test::OIDC - An OpenID Connect provider for the tests

=head1 SYNOPSIS

  my $provider = Lembas::Test::OIDC->serve;
  my $t        = test_app( LEMBAS_OIDC_ISSUER => $provider->issuer );
  $t->app->oidc->ua( $provider->ua );

=head1 DESCRIPTION

Serves discovery, a key set, an authorization endpoint that signs the user in at once and a token endpoint that checks
the code, the client secret and the PKCE verifier. C<claims>, C<fail> (C<discovery>, C<jwks>, C<token>, C<id_token>),
C<signing_key> and C<header_kid> make it misbehave; C<requests> lists what was fetched.

=head2 serve

A new provider, served in this process; C<ua> reaches it and C<issuer> is its URL.

=head2 id_token

A signed ID token for this nonce.

=head2 rotate_key

Signs with a new key, published under a new key id.

=cut
