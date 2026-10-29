use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as test_app);
use Test::NoWarnings;

plan tests => 6;

my $t = test_app();

subtest 'every response' => sub {
    plan tests => 7;
    my $policy = join '; ', "default-src 'self'", "img-src 'self' data:", "style-src 'self'", "script-src 'self'",
        "frame-ancestors 'none'", "base-uri 'none'", "form-action 'self'";
    $t->get_ok('/health')
        ->header_is( 'Content-Security-Policy'   => $policy )
        ->header_is( 'X-Content-Type-Options'    => 'nosniff' )
        ->header_is( 'X-Frame-Options'           => 'DENY' )
        ->header_is( 'Referrer-Policy'           => 'same-origin' )
        ->header_is( 'Cache-Control'             => 'private, no-store' )
        ->header_is( 'Strict-Transport-Security' => undef, 'no HSTS over plain HTTP' );
};

subtest 'request id' => sub {
    plan tests => 4;
    $t->get_ok( '/health' => { 'X-Request-ID' => 'abc-123.def' } )->header_is( 'X-Request-ID' => 'abc-123.def' );
    $t->get_ok( '/health' => { 'X-Request-ID' => 'not <valid>' } )
        ->header_unlike( 'X-Request-ID' => qr/valid/, 'an invalid one is replaced' );
};

subtest 'behind a TLS proxy' => sub {
    plan tests => 2;
    local $ENV{MOJO_REVERSE_PROXY} = 1;
    my $behind_proxy = test_app();
    $behind_proxy->get_ok( '/health' => { 'X-Forwarded-Proto' => 'https' } )
        ->header_is( 'Strict-Transport-Security' => 'max-age=31536000' );
};

subtest 'static files' => sub {
    plan tests => 3;
    $t->get_ok('/robots.txt')->content_like(qr/Disallow: \//)->header_is( 'Cache-Control' => 'no-cache' );
};

subtest 'session cookie' => sub {
    plan tests => 10;
    my $user = create_user($t);
    login_as( $t, $user );
    my $cookie = $t->tx->res->headers->set_cookie;
    like( $cookie, qr/\Alembas=/,      'named lembas' );
    like( $cookie, qr/; HttpOnly/,     'out of reach of scripts' );
    like( $cookie, qr/; SameSite=Lax/, 'sent on the redirect of the sign-in service, not on cross-site posts' );
    unlike( $cookie, qr/; secure/i, 'over plain HTTP' );

    my $https = test_app( LEMBAS_BASE_URL => 'https://lembas.example.org', LEMBAS_SESSION_DAYS => 2 );
    login_as( $https, $user );
    like( $https->tx->res->headers->set_cookie, qr/; secure/i, 'only over HTTPS when the base URL is https' );
    my $expires = Mojo::Date->new( $https->tx->res->headers->set_cookie =~ /expires=([^;]+)/ )->epoch;
    ok( abs( $expires - time - 2 * 86_400 ) < 60, 'expires after LEMBAS_SESSION_DAYS' );
};
