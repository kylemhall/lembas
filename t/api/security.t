use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as reset_db test_app);
use Test::NoWarnings;

plan tests => 6;

my $t = test_app( LEMBAS_ADMIN_EMAILS => 'admin@example.org' );

subtest 'anonymous' => sub {
    plan tests => 4;
    reset_db($t);
    $t->get_ok('/api/v1/me')
        ->status_is(401)
        ->json_is( '/errors/0/message' => 'Invalid or missing API key' )
        ->json_is( '/errors/1/message' => 'Not signed in' );
};

subtest 'API key' => sub {
    plan tests => 8;
    reset_db($t);
    my $user = create_user( $t, email => 'admin@example.org', name => 'Admin' );
    my $key  = $t->app->api_keys->create( $user->{id}, 'test' )->{key};
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $key } )
        ->status_is(200)
        ->json_is( { id => $user->{id}, email => 'admin@example.org', name => 'Admin', is_admin => Mojo::JSON::true } );
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => 'lmb_wrong' } )->status_is(401);

    $t->app->users->set_active( $user->{id}, 0 );
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $key } )->status_is(401);
    ok( !$t->tx->res->cookie('lembas'), 'no session for an API key' );
};

subtest 'session' => sub {
    plan tests => 6;
    reset_db($t);
    my $user = create_user( $t, name => 'Jane' );
    login_as( $t, $user );
    $t->get_ok('/api/v1/me')->status_is(200)->json_is( '/name' => 'Jane' )->json_is( '/is_admin' => Mojo::JSON::false );
};

subtest 'disabled or deleted while signed in' => sub {
    plan tests => 10;
    reset_db($t);
    my $user = create_user($t);
    login_as( $t, $user );
    $t->app->users->set_active( $user->{id}, 0 );
    $t->get_ok('/api/v1/me')->status_is(401);

    # The session was forgotten: enabling the account again does not sign the user in
    $t->app->users->set_active( $user->{id}, 1 );
    $t->get_ok('/api/v1/me')->status_is(401);

    my $deleted = create_user($t);
    login_as( $t, $deleted );
    $t->app->mysql->db->delete( users => { id => $deleted->{id} } );
    $t->get_ok('/api/v1/me')->status_is(401);
};

subtest 'either is enough' => sub {
    plan tests => 4;
    reset_db($t);
    my $user = create_user( $t, name => 'Jane' );
    login_as( $t, $user );
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => 'lmb_wrong' } )->status_is(200);
};
