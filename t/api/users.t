use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as reset_db test_app);
use Test::NoWarnings;
use Mojo::JSON qw(false true);

plan tests => 4;

my $t = test_app( LEMBAS_ADMIN_EMAILS => 'admin@example.org' );

subtest 'GET /api/v1/me' => sub {
    plan tests => 8;
    reset_db($t);
    my $user = create_user( $t, email => 'jane@example.org', name => 'Jane' );
    login_as( $t, $user );
    $t->get_ok('/api/v1/me')
        ->status_is(200)
        ->json_is( { id => $user->{id}, email => 'jane@example.org', name => 'Jane', is_admin => false } );
    $t->get_ok( '/api/v1/me' => { Accept => 'application/xml' } )
        ->status_is(400)
        ->json_is( '/errors/0/path' => '/header/Accept', 'only JSON' );
};

subtest 'GET /api/v1/admin/users' => sub {
    plan tests => 11;
    reset_db($t);
    my $admin = create_user( $t, email => 'admin@example.org' );
    my $jane  = create_user( $t, email => 'jane@example.org' );
    $t->app->mysql->db->insert(
        links => { ending => 'x', long_url => 'https://e/', long_url_hash => 'h', user_id => $jane->{id} } );

    login_as( $t, $jane );
    $t->get_ok('/api/v1/admin/users')->status_is(403)->json_is( '/errors/0/message' => 'Admins only' );

    login_as( $t, $admin );
    $t->get_ok('/api/v1/admin/users')
        ->status_is(200)
        ->json_is( '/users/1/email'       => 'jane@example.org' )
        ->json_is( '/users/1/links_count' => 1 );
};

subtest 'PATCH /api/v1/admin/users/{id}' => sub {
    plan tests => 26;
    reset_db($t);
    my $admin = create_user( $t, email => 'admin@example.org' );
    my $jane  = create_user( $t, email => 'jane@example.org' );
    my $key   = $t->app->api_keys->create( $jane->{id}, 'key' )->{key};

    login_as( $t, $jane );
    $t->patch_ok( "/api/v1/admin/users/$admin->{id}" => json => { is_active => false } )->status_is(403);

    login_as( $t, $admin );
    $t->patch_ok( "/api/v1/admin/users/$jane->{id}" => json => { is_active => false } )
        ->status_is(200)
        ->json_is( '/email'     => 'jane@example.org' )
        ->json_is( '/is_active' => false );
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $key } )->status_is( 200, 'still signed in as the admin' );
    $t->reset_session;
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $key } )
        ->status_is( 401, 'the keys of a disabled account stop working' );

    login_as( $t, $admin );
    $t->patch_ok( "/api/v1/admin/users/$jane->{id}" => json => { is_active => true } )
        ->status_is(200)
        ->json_is( '/is_active' => true );
    $t->patch_ok( "/api/v1/admin/users/$admin->{id}" => json => { is_active => false } )
        ->status_is(400)
        ->json_is( '/errors/0/message' => 'Admins cannot change their own account' );
    $t->patch_ok( '/api/v1/admin/users/999999'      => json => { is_active => false } )->status_is(404);
    $t->patch_ok( "/api/v1/admin/users/$jane->{id}" => json => { is_active => 'no' } )->status_is( 400, 'a boolean' );
};
