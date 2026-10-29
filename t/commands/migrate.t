use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(capture_stdout test_app);
use Test::NoWarnings;
use Lembas::Command::migrate;

plan tests => 6;

my $t          = test_app();
my $migrations = $t->app->mysql->migrations;
my $latest     = $migrations->latest;

sub migrate (@args) {
    return capture_stdout( sub { Lembas::Command::migrate->new( app => $t->app )->run(@args) } );
}

sub tables () { return [ sort @{ $t->app->mysql->db->tables } ] }

subtest 'status' => sub {
    plan tests => 2;
    is( migrate('--status'), "Database version $latest, latest $latest\n", 'the versions' );
    is( $migrations->active, $latest,                                      'nothing changes' );
};

subtest 'down to an empty database' => sub {
    plan tests => 2;
    like( migrate( '--to', 0 ), qr/Migrated from version $latest to 0/, 'migrated down' );
    is_deeply( tables(), ['mojo_migrations'], 'every table is gone' );
};

subtest 'up to the latest version' => sub {
    plan tests => 2;
    like( migrate(), qr/Migrated from version 0 to $latest/, 'migrated up' );
    is_deeply( tables(), [qw(api_keys clicks links mojo_migrations users)], 'every table is back' );
};

subtest 'again' => sub {
    plan tests => 1;
    like( migrate(), qr/Migrated from version $latest to $latest/, 'nothing to do' );
};

subtest 'invalid options' => sub {
    plan tests => 3;
    my $too_far = $latest + 1;
    like( error_of( '--to', $too_far ), qr/--to must be between 0 and $latest/, 'past the latest version' );
    like( error_of( '--to', -1 ),       qr/--to must be between 0 and $latest/, 'before the first version' );

    local $SIG{__WARN__} = sub { };    # Getopt::Long warns about the value
    like( error_of( '--to', 'last' ), qr/Usage: script\/lembas migrate/, 'not a number: the usage' );
};

sub error_of (@args) {
    return eval { migrate(@args); 1 } ? q{} : $@;
}
