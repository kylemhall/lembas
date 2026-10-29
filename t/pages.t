use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as reset_db test_app);
use Test::NoWarnings;

plan tests => 6;

my $t = test_app( LEMBAS_ADMIN_EMAILS => 'admin@example.org' );

# The policy refuses inline scripts, style attributes and event handler attributes
sub csp_clean ( $t, $page ) {
    my $dom = $t->tx->res->dom;
    is( $dom->find('script:not([src])')->size, 0, "$page: no inline script" );
    is( $dom->find('[style]')->size,           0, "$page: no style attribute" );
    my @handlers = grep { /\Aon/ } map { keys %{ $_->attr } } $dom->find('*')->each;
    is_deeply( \@handlers, [], "$page: no event handler attribute" );
    return;
}

subtest 'anonymous' => sub {
    plan tests => 8;
    reset_db($t);
    $t->get_ok('/')
        ->status_is(200)
        ->element_exists( 'a[href="/auth/login"]', 'the sign-in button' )
        ->content_like(qr/The short links of example\.org/)
        ->element_exists_not( 'form[action="/auth/logout"]', 'nobody to sign out' );
    csp_clean( $t, 'the sign-in page' );
};

subtest 'signed in' => sub {
    plan tests => 13;
    reset_db($t);
    login_as( $t, create_user( $t, name => 'Jane Doe' ) );
    $t->get_ok('/')
        ->status_is(200)
        ->element_exists( 'section[x-data="shortener"]',              'the shortener' )
        ->element_exists( 'section[x-data="linkList"][data-all="0"]', 'the links of the user' )
        ->element_exists( 'section[x-data="apiKeys"]',                'the API keys of the user' )
        ->text_like( 'nav span' => qr/Jane Doe/ )
        ->element_exists( 'form[action="/auth/logout"][method="post"] input[name="csrf_token"]', 'sign out' )
        ->element_exists_not( 'a[href="/admin"]', 'not an admin' );
    csp_clean( $t, 'the home page' );
};

subtest 'admins' => sub {
    plan tests => 4;
    reset_db($t);
    login_as( $t, create_user( $t, email => 'admin@example.org' ) );
    $t->get_ok('/')->element_exists( 'a[href="/admin"]', 'the admin page' );
};

subtest 'stats of a link' => sub {
    plan tests => 11;
    reset_db($t);
    $t->get_ok('/links/abc')->status_is(302)->header_is( Location => '/auth/login?return_to=%2Flinks%2Fabc' );
    login_as( $t, create_user($t) );
    $t->get_ok('/links/abc')->status_is(200)->element_exists('section[x-data="linkStats"][data-ending="abc"]');
    csp_clean( $t, 'the stats page' );
};

subtest 'scripts and styles' => sub {
    plan tests => 11;
    $t->get_ok('/js/app.js')->status_is(200)->content_type_like(qr/javascript/);
    $t->get_ok('/css/app.css')->status_is(200)->content_type_like(qr/css/);
    $t->get_ok('/vendor/alpinejs-csp-3.17.5/cdn.min.js')->status_is(200);
    $t->get_ok('/vendor/bootstrap-5.3.8/bootstrap.min.css')->status_is(200)->header_is( 'Cache-Control' => 'no-cache' );
};
