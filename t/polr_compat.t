use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_link create_user reset_db test_app);
use Test::NoWarnings;
use Test::MockModule;

plan tests => 8;

my $t = test_app( LEMBAS_SHORT_URL => 'https://short.example' );
my ( $user, $key );

sub setup () {
    reset_db($t);
    $user = create_user($t);
    $key  = $t->app->api_keys->create( $user->{id}, 'Polr script' )->{key};
    return;
}

subtest 'authentication' => sub {
    plan tests => 12;
    setup();
    $t->get_ok('/api/v2/action/shorten?url=https://example.org/')
        ->status_is(401)
        ->content_is('401 Authentication token required.')
        ->content_type_like(qr{\Atext/plain});
    $t->get_ok('/api/v2/action/shorten?key=wrong&url=https://example.org/&response_type=json')
        ->status_is(401)
        ->json_is( { status_code => 401, error_code => 'AUTH_ERROR', error => 'Authentication token invalid.' } );
    $t->get_ok('/api/v2/action/lookup?url_ending=abc')
        ->status_is(401)
        ->content_is('401 Authentication token required.');
    $t->get_ok("/api/v2/action/lookup?key=$key&url_ending=nothing")->status_is( 404, 'a valid key' );
};

subtest 'shorten' => sub {
    plan tests => 15;
    setup();
    $t->get_ok( '/api/v2/action/shorten' => form => { key => $key, url => 'https://example.org/page' } )
        ->status_is(200)
        ->content_like(qr{\Ahttps://short\.example/[A-Za-z0-9]{6}\z})
        ->header_is( 'Access-Control-Allow-Origin' => '*' )
        ->header_is( Link                          => '</api/v1>; rel="successor-version"' );
    my $short_url = $t->tx->res->body;
    my ($ending) = $short_url =~ m{/([^/]+)\z};
    ok( $t->app->links->find_by_ending($ending)->{is_api}, 'a link made with the API' );

    $t->post_ok(
        '/api/v2/action/shorten' => form => { key => $key, url => 'https://example.org/page', response_type => 'json' }
    )->status_is(200)->json_is(
        q{} => { action => 'shorten', result => $short_url },
        'POST too, and the same link for the same URL'
    );
    $t->get_ok(
        '/api/v2/action/shorten' => form => { key => $key, url => 'https://example.org/', custom_ending => 'polr' } )
        ->content_is('https://short.example/polr');
    $t->get_ok(
        '/api/v2/action/shorten' => form => { key => $key, url => 'https://example.org/x', custom_ending => q{} } )
        ->content_unlike( qr{/\z}, 'an empty custom ending is none' );
    $t->get_ok(
        '/api/v2/action/shorten' => form => { key => $key, is_secret => 'true', url => 'https://example.org/s' } )
        ->status_is( 200, 'secret links are public links' );
};

subtest 'creation errors' => sub {
    plan tests => 9;
    setup();
    create_link( $t, ending => 'taken' );
    $t->get_ok(
        '/api/v2/action/shorten' => form => { key => $key, url => 'https://example.org/', custom_ending => 'taken' } )
        ->status_is(400)
        ->content_is('400 "taken" is already taken');
    $t->get_ok( '/api/v2/action/shorten' => form => { key => $key, url => 'not a URL', response_type => 'json' } )
        ->status_is(400)
        ->json_is( '/error_code' => 'CREATION_ERROR' );
    $t->get_ok( '/api/v2/action/shorten' => form => { key => $key } )
        ->status_is(400)
        ->content_is('400 Invalid or missing parameters.');
};

subtest 'lookup' => sub {
    plan tests => 11;
    setup();
    my $link = create_link( $t, ending => 'look', long_url => 'https://example.org/looked', clicks => 7 );
    $t->get_ok("/api/v2/action/lookup?key=$key&url_ending=look")
        ->status_is(200)
        ->content_is('https://example.org/looked');
    $t->get_ok("/api/v2/action/lookup?key=$key&url_ending=look&response_type=json")
        ->status_is(200)
        ->json_is( '/action'          => 'lookup' )
        ->json_is( '/result/long_url' => 'https://example.org/looked' )
        ->json_is( '/result/clicks'   => 7 )
        ->json_like( '/result/created_at' => qr/\A\d{4}-\d\d-\d\dT/ );
    $t->get_ok("/api/v2/action/lookup?key=$key")->status_is(400);
};

subtest 'not found' => sub {
    plan tests => 3;
    setup();
    $t->get_ok("/api/v2/action/lookup?key=$key&url_ending=nothing&response_type=json")
        ->status_is(404)
        ->json_is( { status_code => 404, error_code => 'NOT_FOUND', error => 'Link not found.' } );
};

subtest 'keys imported from Polr' => sub {
    plan tests => 2;
    setup();
    $t->app->api_keys->import_key( $user->{id}, 'From Polr', '0123456789abcdef0123456789abcd' );
    $t->get_ok('/api/v2/action/shorten?key=0123456789abcdef0123456789abcd&url=https://example.org/old')
        ->status_is( 200, 'still work' );
};

subtest 'unexpected errors' => sub {
    plan tests => 2;
    setup();
    my $links = Test::MockModule->new('Lembas::Model::Links');
    $links->redefine( create => sub (@) { die "The database is gone\n" } );
    $t->get_ok("/api/v2/action/shorten?key=$key&url=https://example.org/")->status_is( 500, 'a bug is a 500' );
};
