use Mojo::Base -strict, -signatures;

use Test::More tests => 6;
use Test::NoWarnings;
use Mojo::Server;
use Test::Mojo;

my %env = (
    LEMBAS_BASE_URL           => 'https://lembas.example.org',
    LEMBAS_DB_URL             => 'mariadb://lembas@db/lembas',
    LEMBAS_SECRETS            => 'test-secret-0123456789',
    LEMBAS_OIDC_CLIENT_ID     => 'client-id',
    LEMBAS_OIDC_CLIENT_SECRET => 'client-secret',
    LEMBAS_ALLOWED_DOMAIN     => 'example.org',
);

subtest 'script/lembas' => sub {
    plan tests => 4;
    local %ENV = ( %ENV, %env );
    my $app = Mojo::Server->new->load_app('script/lembas');
    isa_ok( $app, 'Lembas', 'the application' );
    ok( ( grep { $_ eq 'Lembas::Command' } @{ $app->commands->namespaces } ), 'the commands of Lembas are found' );
    is( $app->config->{base_url}, 'https://lembas.example.org', 'the configuration comes from the environment' );
    is_deeply( $app->secrets, ['test-secret-0123456789'], 'cookies are signed with the configured secrets' );
};

subtest 'invalid configuration' => sub {
    plan tests => 1;
    local %ENV = ( %ENV, %env, LEMBAS_BASE_URL => q{} );
    my $error = eval { Mojo::Server->new->load_app('script/lembas'); 1 } ? q{} : $@;
    like( $error, qr/LEMBAS_BASE_URL is required/, 'the application refuses to start' );
};

subtest 'configuration of the tests' => sub {
    plan tests => 2;
    my $t = Test::Mojo->new( Lembas => { env => { %env, LEMBAS_SITE_NAME => 'Test', LEMBAS_LOG_LEVEL => 'fatal' } } );
    is( $t->app->config->{site_name}, 'Test',  'Test::Mojo gives the environment' );
    is( $t->app->log->level,          'fatal', 'log level' );
};

subtest 'database' => sub {
    plan tests => 3;
    my $t     = Test::Mojo->new( Lembas => { env => { %env, LEMBAS_DB_PASSWORD => 'db-password' } } );
    my $mysql = $t->app->mysql;
    is( $mysql->dsn,              'dbi:MariaDB:dbname=lembas;host=db', 'the database of LEMBAS_DB_URL' );
    is( $mysql->password,         'db-password',                       'the password of LEMBAS_DB_PASSWORD' );
    is( $mysql->migrations->name, 'lembas',                            'the migrations of Lembas' );
};

subtest 'helpers' => sub {
    plan tests => 2;
    my $t = Test::Mojo->new( Lembas => { env => \%env } );
    my $c = $t->app->build_controller;
    isa_ok( $c->links, 'Lembas::Model::Links', 'links' );
    isa_ok( $c->users, 'Lembas::Model::Users', 'users' );
};
