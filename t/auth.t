use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as oidc_authorize reset_db test_app);
use Test::NoWarnings;
use Test::MockModule;
use Mojo::URL;
use Lembas::Test::OIDC;

plan tests => 12;

my $provider = Lembas::Test::OIDC->serve;
my $t        = test_app( LEMBAS_OIDC_ISSUER => $provider->issuer, LEMBAS_ADMIN_EMAILS => 'admin@example.org' );
$t->app->oidc->ua( $provider->ua );
$t->app->routes->get( '/_test/csrf' => sub ($c) { $c->render( text => $c->csrf_token ) } );

my @warnings;
$t->app->log->level('warn')->unsubscribe('message')->on( message => sub ( $, $, @lines ) { push @warnings, "@lines" } );

sub signed_in_as () {
    return $t->get_ok('/api/v1/me')->tx->res->json('/email');
}

subtest 'sign in' => sub {
    plan tests => 14;
    reset_db($t);
    my $callback = oidc_authorize( $t, $provider, return_to => '/links/abc' );
    my $request  = Mojo::URL->new( $t->tx->res->headers->location );
    is( $request->path,                         '/authorize', 'to the sign-in page of the provider' );
    is( $request->query->param('redirect_uri'), 'http://localhost/auth/callback', 'back to the callback' );

    $t->get_ok($callback)->status_is(302)->header_is( Location => '/links/abc', 'back where the user was going' );
    is( signed_in_as(), 'jane@example.org', 'signed in' );
    my $user = $t->app->users->find_by_email('jane@example.org');
    is( $user->{name}, 'Jane Doe', 'the user is created' );
    ok( defined $user->{last_login_at}, 'with the time of the sign-in' );

    $t->get_ok('/auth/login')->status_is(302)->header_is( Location => '/', 'already signed in' );
};

subtest 'sign in again' => sub {
    plan tests => 6;
    $t->reset_session;
    local $provider->{claims} = { name => 'Jane Smith' };
    $t->get_ok( oidc_authorize( $t, $provider ) )->status_is(302)->header_is( Location => '/', 'home by default' );
    is( $t->app->users->find_by_email('jane@example.org')->{name}, 'Jane Smith', 'the name is updated' );
};

subtest 'only paths of Lembas' => sub {
    plan tests => 12;
    for my $elsewhere ( '//evil.example/', 'https://evil.example/', '/\\evil.example' ) {
        $t->reset_session;
        $t->get_ok( oidc_authorize( $t, $provider, return_to => $elsewhere ) )
            ->header_is( Location => '/', $elsewhere );
    }
};

subtest 'the provider is down' => sub {
    plan tests => 4;
    $t->reset_session;
    $provider->fail->{discovery} = 1;
    $t->app->oidc->{discovery} = undef;
    $t->get_ok('/auth/login')->status_is(503)->text_is( h1 => 'Sign-in failed' );
    like( $warnings[-1], qr/Sign-in failed: oidc_unavailable \(.*Internal Server Error\)/, 'logged, with the details' );
    delete $provider->fail->{discovery};
};

subtest 'cancelled, incomplete or expired' => sub {
    plan tests => 26;
    $t->reset_session;
    my $callback = Mojo::URL->new( oidc_authorize( $t, $provider ) );
    $t->get_ok('/auth/callback?error=access_denied')->status_is(400)->text_like( p => qr/cancelled/ );

    $callback = Mojo::URL->new( oidc_authorize( $t, $provider ) );
    $t->get_ok( $callback->clone->query( code => $callback->query->param('code') ) )
        ->status_is(400)
        ->text_like( p => qr/incomplete/, 'no state' );
    $t->get_ok( $callback->clone->query( state => $callback->query->param('state') ) )
        ->status_is(400)
        ->text_like( p => qr/incomplete/, 'no code' );
    $t->get_ok($callback)->status_is(400)->text_like( p => qr/expired/, 'one use only: the sign-in is gone' );

    $callback = Mojo::URL->new( oidc_authorize( $t, $provider ) );
    my $now = $t->app->oidc->now;
    $t->app->oidc->now( sub { time + 601 } );
    $t->get_ok($callback)->status_is(400)->text_like( p => qr/expired/, 'ten minutes to sign in' );
    $t->app->oidc->now($now);

    $callback = Mojo::URL->new( oidc_authorize( $t, $provider ) );
    $t->get_ok( $callback->clone->query( { state => 'forged' } ) )
        ->status_is(400)
        ->text_like( p => qr/does not match/, 'another state' );
};

subtest 'the provider refuses the code' => sub {
    plan tests => 5;
    $t->reset_session;
    my $callback = oidc_authorize( $t, $provider );
    $provider->fail->{token} = 1;
    $t->get_ok($callback)->status_is(502);
    delete $provider->fail->{token};
    like( $warnings[-1], qr/Sign-in failed: oidc_exchange_failed \(Bad Request\)/, 'logged' );
};

subtest 'invalid tokens' => sub {
    plan tests => 10;
    $t->reset_session;
    local $provider->{claims} = { hd => 'evil.example', email => 'jane@evil.example' };
    my $callback = oidc_authorize( $t, $provider );
    $t->get_ok($callback)->status_is(403)->text_is( p => 'Only example.org Google accounts can sign in' );
    like( $warnings[-1], qr/Sign-in failed: oidc_wrong_domain\z/, 'logged' );

    local $provider->{claims} = { nonce => 'replayed' };
    $t->get_ok( oidc_authorize( $t, $provider ) )->status_is(401);
};

subtest 'disabled account' => sub {
    plan tests => 7;
    reset_db($t);
    create_user( $t, email => 'jane@example.org', is_active => 0 );
    $t->get_ok( oidc_authorize( $t, $provider ) )->status_is(403)->text_is( p => 'This account is disabled' );
    ok( !$t->get_ok('/api/v1/me')->tx->res->is_success, 'not signed in' );
};

subtest 'sign out' => sub {
    plan tests => 10;
    reset_db($t);
    login_as( $t, create_user($t) );
    $t->post_ok('/auth/logout')->status_is( 403, 'not without the token of the page' );
    my $token = $t->get_ok('/_test/csrf')->tx->res->body;
    $t->post_ok( '/auth/logout' => form => { csrf_token => $token } )->status_is(302)->header_is( Location => '/' );
    ok( !$t->get_ok('/api/v1/me')->tx->res->is_success, 'signed out' );
};

subtest 'unexpected errors' => sub {
    plan tests => 4;
    reset_db($t);
    my $users = Test::MockModule->new('Lembas::Model::Users');
    $users->redefine( find_or_create_from_claims => sub (@) { die "The database is gone\n" } );
    local $t->app->log->{level} = 'fatal';
    $t->get_ok( oidc_authorize( $t, $provider ) )->status_is( 500, 'a bug is a 500' );
};

subtest 'admins' => sub {
    plan tests => 5;
    reset_db($t);
    local $provider->{claims} = { email => 'admin@example.org' };
    $t->get_ok( oidc_authorize( $t, $provider ) );
    ok( $t->get_ok('/api/v1/me')->tx->res->json('/is_admin'), 'from LEMBAS_ADMIN_EMAILS' );
};
