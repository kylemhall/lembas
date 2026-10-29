use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(test_app);
use Test::NoWarnings;

plan tests => 5;

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
