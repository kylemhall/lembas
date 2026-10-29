use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(test_app);
use Test::NoWarnings;

plan tests => 6;

my $t = test_app();

subtest 'liveness' => sub {
    plan tests => 3;
    $t->get_ok('/health')->status_is(200)->json_is( { status => 'ok' } );
};

subtest 'ready' => sub {
    plan tests => 3;
    $t->get_ok('/ready')->status_is(200)->json_is( { status => 'ok' } );
};

subtest 'migrations pending' => sub {
    plan tests => 3;
    my $migrations = $t->app->mysql->migrations;
    $migrations->migrate(0);
    $t->get_ok('/ready')->status_is(503)->json_is( { status => 'unavailable', reason => 'migrations_pending' } );
    $migrations->migrate;
};

subtest 'database down' => sub {
    plan tests => 4;
    my $down = test_app( LEMBAS_DB_URL => 'mariadb://nobody@127.0.0.1:1/nothing' );
    my @warnings;
    $down->app->log->level('warn')
        ->unsubscribe('message')
        ->on( message => sub ( $, $level, @lines ) { push @warnings, "@lines" } );
    $down->get_ok('/ready')->status_is(503)->json_is( { status => 'unavailable', reason => 'db' } );
    like( "@warnings", qr/Not ready, the database cannot be reached/, 'the reason is logged' );
};

subtest 'request log' => sub {
    plan tests => 4;
    my @lines;
    $t->app->log->level('debug')
        ->unsubscribe('message')
        ->on( message => sub ( $, $level, @message ) { push @lines, "$level @message" } );
    $t->get_ok('/health');
    $t->get_ok( '/nowhere' => { 'X-Request-ID' => 'from-the-proxy' } );
    like( $lines[0],  qr{\Adebug GET /health 200 [0-9.]+ms id=\S+\z}, 'probes are logged at the debug level' );
    like( $lines[-1], qr{\Ainfo GET /nowhere 404 [0-9.]+ms id=from-the-proxy\z}, 'other requests at the info level' );
};
