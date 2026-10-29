use Mojo::Base -strict, -signatures;

use Test::More tests => 11;
use Test::NoWarnings;
use Crypt::PK::RSA;
use Digest::SHA  qw(sha256);
use MIME::Base64 qw(encode_base64url);
use Mojo::URL;
use Lembas::Model::OIDC;
use Lembas::Test::OIDC;

my $provider = Lembas::Test::OIDC->serve;
my $clock    = time;

sub oidc (%attributes) {
    return Lembas::Model::OIDC->new(
        issuer         => $provider->issuer,
        client_id      => 'lembas-test',
        client_secret  => 'test-client-secret',
        redirect_url   => 'http://localhost/auth/callback',
        allowed_domain => 'example.org',
        ua             => $provider->ua,
        now            => sub { $clock },
        %attributes,
    );
}

# The Lembas::Error thrown by the code, or undef
sub error_of ($code) {
    return eval { $code->(); 1 } ? undef : $@;
}

sub fetched ($what) {
    return scalar grep { $_ eq $what } splice @{ $provider->requests };
}

# The provider signs the user in at once: the code it sends back
sub code_for ($request) {
    return Mojo::URL->new( $provider->ua->get( $request->{url} )->res->headers->location )->query->param('code');
}

subtest 'defaults' => sub {
    plan tests => 3;
    my $oidc = Lembas::Model::OIDC->new;
    isa_ok( $oidc->ua, 'Mojo::UserAgent', 'the user agent' );
    is_deeply( [ $oidc->ua->connect_timeout, $oidc->ua->request_timeout ], [ 5, 10 ], 'with short timeouts' );
    ok( abs( $oidc->now->() - time ) < 5, 'the clock' );
};

subtest 'discovery() tests' => sub {
    plan tests => 7;
    splice @{ $provider->requests };
    my $oidc = oidc();
    is( $oidc->discovery->{token_endpoint}, $provider->issuer . '/token', 'the discovery document' );
    $oidc->discovery;
    is( fetched('discovery'), 1, 'fetched once' );
    $clock += 3600;
    $oidc->discovery;
    is( fetched('discovery'), 1, 'and again after an hour' );

    $provider->fail->{discovery} = 1;
    my $error = error_of( sub { oidc()->discovery } );
    delete $provider->fail->{discovery};
    is( $error->code,   'oidc_unavailable', 'the provider is down' );
    is( $error->status, 503,                'service unavailable' );
    like(
        $error->detail, qr{/.well-known/openid-configuration: Internal Server Error},
        'the details are for the logs'
    );
    unlike( $error->message, qr/well-known/, 'not for the user' );
};

subtest 'jwks() tests' => sub {
    plan tests => 6;
    my $oidc = oidc();
    splice @{ $provider->requests };
    is( $oidc->jwks(0)->{keys}[0]{kid}, 'key-1', 'the keys of the provider' );
    $oidc->jwks(0);
    $oidc->jwks(1);
    is( fetched('jwks'), 1, 'fetched once, and not again within a minute' );
    $clock += 61;
    $oidc->jwks(1);
    is( fetched('jwks'), 1, 'refreshed after a minute' );
    $oidc->jwks(0);
    is( fetched('jwks'), 0, 'but only when asked' );
    $clock += 3600;
    $oidc->jwks(0);
    is( fetched('jwks'), 1, 'and every hour' );

    $provider->fail->{jwks} = 1;
    is( error_of( sub { oidc()->jwks(0) } )->code, 'oidc_unavailable', 'the provider is down' );
    delete $provider->fail->{jwks};
};

subtest 'authorization_request() tests' => sub {
    plan tests => 7;
    my $request = oidc()->authorization_request;
    my $url     = Mojo::URL->new( $request->{url} );
    is( $url->path, '/authorize', 'the sign-in page of the provider' );
    is_deeply(
        $url->query->to_hash,
        {
            response_type         => 'code',
            client_id             => 'lembas-test',
            redirect_uri          => 'http://localhost/auth/callback',
            scope                 => 'openid email profile',
            state                 => $request->{state},
            nonce                 => $request->{nonce},
            code_challenge        => encode_base64url( sha256( $request->{code_verifier} ) ),
            code_challenge_method => 'S256',
            hd                    => 'example.org',
            prompt                => 'select_account',
        },
        'the code flow, with PKCE and the Workspace domain'
    );
    like( $request->{$_}, qr/\A[\w-]{43}\z/, "a random $_" ) for qw(state nonce code_verifier);
    my $other = oidc()->authorization_request;
    isnt( $other->{state}, $request->{state}, 'different every time' );
    isnt( $other->{nonce}, $request->{nonce}, 'the nonce too' );
};

subtest 'exchange_code() tests' => sub {
    plan tests => 6;
    my $oidc    = oidc();
    my $request = $oidc->authorization_request;
    my $code    = code_for($request);
    like( $oidc->exchange_code( $code, $request->{code_verifier} ), qr/\A[\w-]+\.[\w-]+\.[\w-]+\z/, 'an ID token' );

    my $error = error_of( sub { $oidc->exchange_code( $code, 'another verifier' ) } );
    is_deeply( [ $error->code, $error->status ], [ 'oidc_exchange_failed', 502 ], 'not without the verifier' );
    is( $error->detail, 'Bad Request', 'the details are for the logs' );
    is(
        error_of( sub { $oidc->exchange_code( 'code-unknown', $request->{code_verifier} ) } )->code,
        'oidc_exchange_failed', 'an unknown code'
    );

    $provider->fail->{id_token} = 1;
    my $missing = error_of( sub { $oidc->exchange_code( $code, $request->{code_verifier} ) } );
    delete $provider->fail->{id_token};
    is( $missing->code,   'oidc_exchange_failed',         'a response without an ID token' );
    is( $missing->detail, 'The response has no id_token', 'says so in the logs' );
};

subtest 'verify_id_token() tests' => sub {
    plan tests => 4;
    my $oidc = oidc();
    is_deeply(
        $oidc->verify_id_token( $provider->id_token('n1'), 'n1' ),
        { sub => 'google-jane', email => 'jane@example.org', name => 'Jane Doe' },
        'the user'
    );
    local $provider->{claims} = { email => 'Jane@Example.org', name => undef };
    is_deeply(
        $oidc->verify_id_token( $provider->id_token('n2'), 'n2' ),
        { sub => 'google-jane', email => 'jane@example.org', name => q{} },
        'the email in lower case, no name'
    );
    local $provider->{claims} = { iss => Mojo::URL->new( $provider->issuer )->host_port };
    ok( $oidc->verify_id_token( $provider->id_token('n3'), 'n3' ), 'an issuer without its scheme, like Google\'s' );
    local $provider->{claims} = { nbf => time + 3600 };
    is(
        error_of( sub { $oidc->verify_id_token( $provider->id_token('n4'), 'n4' ) } )->code,
        'oidc_bad_token', 'not before its time'
    );
};

subtest 'invalid tokens' => sub {
    my %invalid = (
        'another audience' => [ { aud            => 'someone-else' },         'oidc_bad_token',        401 ],
        'another issuer'   => [ { iss            => 'https://evil.example' }, 'oidc_bad_token',        401 ],
        'expired'          => [ { exp            => time - 3600 },            'oidc_expired',          401 ],
        'no expiry'        => [ { exp            => undef },                  'oidc_bad_token',        401 ],
        'another nonce'    => [ { nonce          => 'replayed' },             'oidc_nonce_mismatch',   401 ],
        'no nonce'         => [ { nonce          => undef },                  'oidc_nonce_mismatch',   401 ],
        'unverified email' => [ { email_verified => Mojo::JSON::false },      'oidc_email_unverified', 403 ],
        'personal account' => [ { hd             => undef },                  'oidc_wrong_domain',     403 ],
        'another domain'   => [ { hd             => 'evil.example' },         'oidc_wrong_domain',     403 ],
        'another email'    => [ { email          => 'jane@evil.example' },    'oidc_wrong_domain',     403 ],
        'no email'         => [ { email          => undef },                  'oidc_wrong_domain',     403 ],
    );
    plan tests => 1 + keys %invalid;
    my $oidc = oidc();
    for my $case ( sort keys %invalid ) {
        my ( $claims, $code, $status ) = @{ $invalid{$case} };
        local $provider->{claims} = $claims;
        my $error = error_of( sub { $oidc->verify_id_token( $provider->id_token('nonce'), 'nonce' ) } );
        is_deeply( [ $error->code, $error->status ], [ $code, $status ], $case );
    }
    local $provider->{claims} = { hd => 'evil.example' };
    like(
        error_of( sub { $oidc->verify_id_token( $provider->id_token('nonce'), 'nonce' ) } )->message,
        qr/Only example\.org Google accounts can sign in/, 'says which accounts can'
    );
};

subtest 'signatures' => sub {
    plan tests => 2;
    my $oidc = oidc();
    local $provider->{signing_key} = Crypt::PK::RSA->new->generate_key(256);
    is(
        error_of( sub { $oidc->verify_id_token( $provider->id_token('n'), 'n' ) } )->code, 'oidc_bad_token',
        'signed by another key under the same key id'
    );
    local $provider->{signing_key} = $provider->key;
    local $provider->{header_kid}  = 'unknown';
    $clock += 61;
    is(
        error_of( sub { $oidc->verify_id_token( $provider->id_token('n'), 'n' ) } )->code, 'oidc_bad_token',
        'a key id the provider does not have, even after another look'
    );
};

subtest 'rotated keys' => sub {
    plan tests => 4;
    my $oidc = oidc();
    $oidc->jwks(0);
    splice @{ $provider->requests };
    my $previous = { key => $provider->key, kid => $provider->kid };
    $provider->rotate_key;

    is(
        error_of( sub { $oidc->verify_id_token( $provider->id_token('n'), 'n' ) } )->code, 'oidc_bad_token',
        'the new key within a minute of the last fetch: not fetched again'
    );
    is( fetched('jwks'), 0, 'nothing fetched' );
    $clock += 61;
    is(
        $oidc->verify_id_token( $provider->id_token('n'), 'n' )->{email}, 'jane@example.org',
        'after a minute, the keys are fetched again and the token verifies'
    );
    is( fetched('jwks'), 1, 'fetched once' );

    $provider->key( $previous->{key} )->kid( $previous->{kid} );
    $provider->signing_key( $previous->{key} )->header_kid( $previous->{kid} );
};

subtest 'unreachable keys' => sub {
    plan tests => 1;
    $provider->fail->{jwks} = 1;
    is(
        error_of( sub { oidc()->verify_id_token( $provider->id_token('n'), 'n' ) } )->code, 'oidc_unavailable',
        'the keys cannot be fetched'
    );
    delete $provider->fail->{jwks};
};
