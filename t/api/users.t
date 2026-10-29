use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user login_as reset_db test_app);
use Test::NoWarnings;
use Mojo::JSON qw(false true);

plan tests => 2;

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
