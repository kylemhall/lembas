use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_user reset_db test_app);
use Test::NoWarnings;
use Digest::SHA qw(sha256_hex);

plan tests => 7;

my $t        = test_app();
my $api_keys = $t->app->api_keys;
my $db       = $t->app->mysql->db;

subtest 'create() tests' => sub {
    plan tests => 6;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    my $api_key = $api_keys->create( $user_id, 'Deploy script' );
    like( $api_key->{key}, qr/\Almb_[A-Za-z0-9]{40}\z/, 'a random key' );
    is( $api_key->{label},        'Deploy script',                  'its label' );
    is( $api_key->{key_prefix},   substr( $api_key->{key}, 0, 12 ), 'the start of the key, to recognize it' );
    is( $api_key->{last_used_at}, undef,                            'never used' );
    my $stored = $db->select( api_keys => '*', { id => $api_key->{id} } )->hash;
    is( $stored->{key_hash}, sha256_hex( $api_key->{key} ), 'its hash is stored' );
    ok( !( grep { defined && $_ eq $api_key->{key} } values %$stored ), 'never the key itself' );
};

subtest 'import_key() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    my $api_key = $api_keys->import_key( $user_id, 'From Polr', 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3' );
    is( $api_key->{key_prefix},                                    'a1b2c3d4e5f6', 'the start of the key' );
    is( $api_keys->authenticate('a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3'), $user_id,       'it works' );
};

subtest 'list() tests' => sub {
    plan tests => 3;
    reset_db($t);
    my ( $jane, $john ) = map { create_user($t)->{id} } 1 .. 2;
    $api_keys->create( $jane, $_ ) for qw(first second);
    $api_keys->create( $john, 'other' );
    my $list = $api_keys->list($jane);
    is_deeply( [ map { $_->{label} } @$list ], [qw(first second)], 'the keys of the user, oldest first' );
    ok( !exists $list->[0]{key},      'not the keys themselves' );
    ok( !exists $list->[0]{key_hash}, 'nor their hashes' );
};

subtest 'revoke() tests' => sub {
    plan tests => 4;
    reset_db($t);
    my ( $jane, $john ) = map { create_user($t)->{id} } 1 .. 2;
    my $api_key = $api_keys->create( $jane, 'key' );
    is( $api_keys->revoke( $john, $api_key->{id} ), 0, 'not by another user' );
    is( $api_keys->revoke( $jane, $api_key->{id} ), 1, 'revoked' );
    is( $api_keys->authenticate( $api_key->{key} ), undef, 'it does not work anymore' );
    is_deeply( $api_keys->list($jane), [], 'gone' );
};

subtest 'authenticate() tests' => sub {
    plan tests => 5;
    reset_db($t);
    my $user    = create_user($t);
    my $api_key = $api_keys->create( $user->{id}, 'key' );
    is( $api_keys->authenticate( $api_key->{key} ), $user->{id}, 'the user of the key' );
    like( $api_keys->list( $user->{id} )->[0]{last_used_at}, qr/\A\d{4}-/, 'its use is recorded' );
    is( $api_keys->authenticate('lmb_wrong'), undef, 'an unknown key' );
    is( $api_keys->authenticate(q{}),         undef, 'no key' );

    $db->update( users => { is_active => 0 }, { id => $user->{id} } );
    is( $api_keys->authenticate( $api_key->{key} ), undef, 'not for a disabled account' );
};

subtest 'is_known() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $api_key = $api_keys->create( create_user($t)->{id}, 'key' );
    ok( $api_keys->is_known( $api_key->{key} ), 'known' );
    ok( !$api_keys->is_known('lmb_nope'),       'unknown' );
};
