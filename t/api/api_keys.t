use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as reset_db test_app);
use Test::NoWarnings;

plan tests => 5;

my $t = test_app();

subtest 'GET /api/v1/api_keys' => sub {
    plan tests => 9;
    reset_db($t);
    my $user = create_user($t);
    login_as( $t, $user );
    $t->get_ok('/api/v1/api_keys')->status_is(200)->json_is( '/api_keys' => [] );
    $t->app->api_keys->create( $user->{id}, 'Deploy' );
    $t->get_ok('/api/v1/api_keys')
        ->status_is(200)
        ->json_is( '/api_keys/0/label' => 'Deploy' )
        ->json_hasnt('/api_keys/0/key');
};

subtest 'POST /api/v1/api_keys' => sub {
    plan tests => 15;
    reset_db($t);
    login_as( $t, create_user( $t, name => 'Jane' ) );
    $t->post_ok( '/api/v1/api_keys' => json => { label => 'Deploy' } )
        ->status_is(201)
        ->json_is( '/label' => 'Deploy' )
        ->json_like( '/key' => qr/\Almb_/, 'the key, this once' );
    my $key = $t->tx->res->json('/key');
    $t->reset_session;
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $key } )->status_is(200)->json_is( '/name' => 'Jane', 'it works' );

    $t->post_ok( '/api/v1/api_keys' => { 'X-Api-Key' => $key } => json => { label => 'More' } )
        ->status_is( 401, 'an API key cannot make keys' );
    login_as( $t, create_user($t) );
    $t->post_ok( '/api/v1/api_keys' => json => { label => q{} } )->status_is( 400, 'a label is needed' );
};

subtest 'DELETE /api/v1/api_keys/{id}' => sub {
    plan tests => 14;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    my $janes = $t->app->api_keys->create( $jane->{id}, 'Jane' );
    my $johns = $t->app->api_keys->create( $john->{id}, 'John' );
    login_as( $t, $jane );
    $t->delete_ok("/api/v1/api_keys/$johns->{id}")->status_is( 404, 'not the key of someone else' );
    $t->delete_ok("/api/v1/api_keys/$janes->{id}")->status_is(204);
    $t->delete_ok("/api/v1/api_keys/$janes->{id}")->status_is( 404, 'gone' );
    $t->delete_ok('/api/v1/api_keys/first')->status_is( 400, 'ids are numbers' );

    $t->reset_session;
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $janes->{key} } )->status_is( 401, 'a revoked key does not work' );
    $t->get_ok( '/api/v1/me' => { 'X-Api-Key' => $johns->{key} } )->status_is( 200, 'the others do' );
};

subtest 'only with a session' => sub {
    plan tests => 2;
    reset_db($t);
    my $user = create_user($t);
    my $key  = $t->app->api_keys->create( $user->{id}, 'key' )->{key};
    $t->get_ok( '/api/v1/api_keys' => { 'X-Api-Key' => $key } )->status_is(401);
};
