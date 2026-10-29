use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(test_app);
use Test::NoWarnings;
use Mojo::File;

plan tests => 3;

local $ENV{MOJO_MODE} = 'production';
my $t = test_app();
$t->app->log->handle( Mojo::File->new('/dev/null')->open('>') );
$t->app->routes->get( '/_test/die' => sub ($c) { die "Broken\n" } );

subtest 'not found' => sub {
    plan tests => 4;
    $t->get_ok('/nothing')
        ->status_is(404)
        ->text_is( h1 => 'Nothing here' )
        ->text_like( title => qr/Not found - Lembas/ );
};

subtest 'exception' => sub {
    plan tests => 5;
    $t->get_ok( '/_test/die' => { 'X-Request-ID' => 'req-123' } )
        ->status_is(500)
        ->text_is( h1   => 'Something went wrong' )
        ->text_is( code => 'req-123', 'the request id, to find the error in the logs' )
        ->content_unlike( qr/Broken/, 'the error itself is not shown' );
};
