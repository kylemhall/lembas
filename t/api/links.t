use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_link create_user login_as reset_db test_app);
use Test::NoWarnings;
use Test::MockModule;
use Mojo::JSON qw(false true);

plan tests => 9;

my $t = test_app( LEMBAS_ADMIN_EMAILS => 'admin@example.org', LEMBAS_SHORT_URL => 'https://short.example' );

subtest 'GET /api/v1/links' => sub {
    plan tests => 28;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    create_link( $t, ending => "jane$_", user_id => $jane->{id}, created_at => "2026-01-0$_ 00:00:00" ) for 1 .. 3;
    create_link( $t, ending => 'john1', user_id => $john->{id} );
    login_as( $t, $jane );

    $t->get_ok('/api/v1/links')
        ->status_is(200)
        ->json_is( '/total'                 => 3 )
        ->json_is( '/page'                  => 1,       'the first page by default' )
        ->json_is( '/per_page'              => 25,      'of 25 links' )
        ->json_is( '/links/0/ending'        => 'jane3', 'newest first' )
        ->json_is( '/links/0/short_url'     => 'https://short.example/jane3' )
        ->json_is( '/links/0/creator_email' => $jane->{email} );
    $t->get_ok('/api/v1/links?per_page=2&page=2')->status_is(200)->json_is( '/links/0/ending' => 'jane1' );
    $t->get_ok('/api/v1/links?q=ne2')->status_is(200)->json_is( '/total' => 1 );
    $t->get_ok('/api/v1/links?all=true')
        ->status_is(403)
        ->json_is( '/errors/0/message' => 'Only admins can list every link' );
    $t->get_ok('/api/v1/links?per_page=101')->status_is(400);
    $t->get_ok('/api/v1/links?page=0')->status_is(400);

    login_as( $t, create_user( $t, email => 'admin@example.org' ) );
    $t->get_ok('/api/v1/links?all=1')->status_is(200)->json_is( '/total' => 4, 'admins see every link' );
};

subtest 'POST /api/v1/links' => sub {
    plan tests => 33;
    reset_db($t);
    my $user = create_user($t);
    login_as( $t, $user );

    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/page' } )
        ->status_is(201)
        ->json_like( '/ending' => qr/\A[A-Za-z0-9]{6}\z/ )
        ->json_is( '/long_url'  => 'https://example.org/page' )
        ->json_is( '/is_custom' => false )
        ->json_is( '/is_api'    => false, 'not with an API key' );
    my $ending = $t->tx->res->json('/ending');
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/page' } )
        ->status_is(200)
        ->json_is( '/ending' => $ending, 'the link already made for this URL' );

    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/page', ending => 'Mine' } )
        ->status_is(201)
        ->json_is( '/ending'    => 'Mine' )
        ->json_is( '/is_custom' => true );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/other', ending => 'Mine' } )
        ->status_is(409)
        ->json_is( '/errors/0/message' => '"Mine" is already taken' );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/', ending => 'admin' } )
        ->status_is(400)
        ->json_is( '/errors/0/message' => '"admin" is reserved' );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/', ending => 'a b' } )
        ->status_is( 400, 'an invalid ending' );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'mailto:someone@example.org' } )
        ->status_is(400)
        ->json_like( '/errors/0/message' => qr/must be an http or https URL/ );
    $t->post_ok( '/api/v1/links' => json => {} )->status_is( 400, 'no long URL' );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/', clicks => 9 } )
        ->status_is( 400, 'nothing else' );

    my $key = $t->app->api_keys->create( $user->{id}, 'script' )->{key};
    $t->reset_session;
    $t->post_ok( '/api/v1/links' => { 'X-Api-Key' => $key } => json => { long_url => 'https://example.org/api' } )
        ->status_is(201)
        ->json_is( '/is_api' => true, 'with an API key' );
};

subtest 'GET /api/v1/links/{ending}' => sub {
    plan tests => 20;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    create_link( $t, ending => 'janes', user_id => $jane->{id} );
    create_link( $t, ending => 'johns', user_id => $john->{id} );
    create_link( $t, ending => 'polr',  user_id => undef );
    login_as( $t, $jane );

    $t->get_ok('/api/v1/links/janes')->status_is(200)->json_is( '/ending' => 'janes' );
    $t->get_ok('/api/v1/links/johns')
        ->status_is(403)
        ->json_is( '/errors/0/message' => 'This link belongs to someone else' );
    $t->get_ok('/api/v1/links/polr')->status_is( 403, 'nor the links imported from Polr without a user' );
    $t->get_ok('/api/v1/links/nothing')->status_is(404);
    $t->get_ok('/api/v1/links/no.dots')->status_is( 404, 'no route for what is not an ending' );
    $t->get_ok('/api/v1/links/with%20space')->status_is( 400, 'or the specification refuses it' );

    login_as( $t, create_user( $t, email => 'admin@example.org' ) );
    $t->get_ok('/api/v1/links/johns')->status_is( 200, 'admins see every link' );
};

subtest 'PATCH /api/v1/links/{ending}' => sub {
    plan tests => 14;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    create_link( $t, ending => 'janes', user_id => $jane->{id} );
    create_link( $t, ending => 'johns', user_id => $john->{id} );
    login_as( $t, $jane );

    $t->patch_ok( '/api/v1/links/janes' => json => { long_url => 'https://example.org/new' } )
        ->status_is(200)
        ->json_is( '/long_url' => 'https://example.org/new' );
    $t->patch_ok( '/api/v1/links/janes' => json => { is_disabled => true } )
        ->status_is(200)
        ->json_is( '/is_disabled' => true );
    $t->patch_ok( '/api/v1/links/janes' => json => { long_url => 'ftp://example.org/' } )->status_is(400);
    $t->patch_ok( '/api/v1/links/janes' => json => {} )->status_is( 400, 'something to change' );
    $t->patch_ok( '/api/v1/links/johns' => json => { is_disabled => true } )->status_is(403);
};

subtest 'DELETE /api/v1/links/{ending}' => sub {
    plan tests => 11;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    create_link( $t, ending => 'janes', user_id => $jane->{id} );
    create_link( $t, ending => 'johns', user_id => $john->{id} );
    login_as( $t, $jane );

    $t->delete_ok('/api/v1/links/janes')->status_is(204)->content_is(q{});
    $t->get_ok('/api/v1/links/janes')->status_is( 404, 'gone' );
    $t->delete_ok('/api/v1/links/johns')->status_is(403);
    $t->delete_ok('/api/v1/links/with%20space')->status_is(400);
};

subtest 'unexpected errors' => sub {
    plan tests => 4;
    reset_db($t);
    login_as( $t, create_user($t) );
    my $links = Test::MockModule->new('Lembas::Model::Links');
    $links->redefine( create => sub (@) { die "The database is gone\n" } );
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/' } )
        ->status_is( 500, 'a bug is a 500' );
};

subtest 'anonymous' => sub {
    plan tests => 4;
    reset_db($t);
    $t->get_ok('/api/v1/links')->status_is(401);
    $t->post_ok( '/api/v1/links' => json => { long_url => 'https://example.org/' } )->status_is(401);
};

subtest 'the response is checked against the specification' => sub {
    plan tests => 4;
    reset_db($t);
    login_as( $t, create_user($t) );
    my $links = Test::MockModule->new('Lembas::Model::Links');
    $links->redefine( list => sub (@) { return { links => [ { ending => 'incomplete' } ], total => 1 } } );
    is( $t->get_ok('/api/v1/links')->tx->res->code, 500, 'an invalid response is a 500' );
};
