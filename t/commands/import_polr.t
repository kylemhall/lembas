use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(capture_stdout create_database create_link create_user test_app);
use Test::NoWarnings;
use Mojo::File qw(tempdir);
use Mojo::URL;
use Mojo::mysql;
use Lembas::Command::import_polr;
use Lembas::Model::ApiKeys;

plan tests => 6;

my $t        = test_app( LEMBAS_ALLOWED_DOMAIN => 'example.org' );
my $db       = $t->app->mysql->db;
my $polr_url = create_database( 'polr', 't/fixtures/polr_schema.sql' );
my $polr     = Mojo::mysql->new($polr_url)->db;

sub polr_user (%columns) {
    return $polr->insert(
        users => { password => 'x', ip => '127.0.0.1', recovery_key => 'r', role => q{}, active => '1', %columns } );
}

sub polr_link (%columns) {
    return $polr->insert( links => { ip => '127.0.0.1', creator => q{}, secret_key => q{}, %columns } )->last_insert_id;
}

sub import_polr (@args) {
    return capture_stdout( sub { Lembas::Command::import_polr->new( app => $t->app )->run(@args) } );
}

sub count ($table) { return $db->select( $table, 'count(*)' )->array->[0] }

my $admin_key = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5';
polr_user(
    username   => 'admin',
    email      => ' Admin@Example.org ',
    role       => 'admin',
    api_key    => $admin_key,
    api_active => 1,
    created_at => '2017-01-02 03:04:05'
);
polr_user( username => 'jane',     email => 'jane@example.org',  api_key => 'unused',  api_active => 0 );
polr_user( username => 'gone',     email => 'gone@example.org',  api_key => 'gonekey', api_active => 1, active => '0' );
polr_user( username => 'outsider', email => 'someone@other.org', api_key => 'otherkey', api_active => 1 );
polr_user( username => 'nokey',    email => 'nokey@example.org', api_key => undef,      api_active => 1 );

my $docs = polr_link(
    short_url  => '3Fz',
    long_url   => 'https://example.org/docs',
    creator    => 'admin',
    clicks     => 5,
    created_at => '2017-05-06 07:08:09',
    updated_at => '2018-01-01 00:00:00'
);
polr_link(
    short_url   => 'custom', long_url => 'https://example.org/c', creator => 'jane', is_custom => 1,
    is_disabled => 1,        is_api   => 1
);
polr_link( short_url => 'secret',  long_url => 'https://example.org/s', creator => 'jane', secret_key => 'ab12' );
polr_link( short_url => 'anon',    long_url => 'https://example.org/a' );
polr_link( short_url => 'anonapi', long_url => 'https://example.org/aa', creator => 'ANONIP-192.0.2.1' );
polr_link( short_url => 'ghost',   long_url => 'https://example.org/g',  creator => 'a-deleted-user' );
polr_link( short_url => 'huge',    long_url => 'https://example.org/' . ( 'x' x 70_000 ), creator => 'admin' );
polr_link( short_url => 'cafe',    long_url => "https://example.org/caf\x{e9}",           creator => 'admin' );
polr_link( short_url => 'taken',   long_url => 'https://example.org/t',                   creator => 'admin' );
$polr->insert(
    clicks => {
        ip           => '192.0.2.9',
        country      => 'US',
        referer      => 'https://chat.example/room',
        referer_host => 'chat.example',
        user_agent   => 'y' x 600,
        link_id      => $docs,
        created_at   => '2017-06-01 10:00:00'
    }
);
$polr->insert( clicks => { ip => '192.0.2.9', link_id => $docs } );

my $jane = create_user( $t, email => 'jane@example.org', name => 'Jane' );
create_link( $t, ending => 'taken', long_url => 'https://example.org/already' );

subtest 'dry run' => sub {
    plan tests => 4;
    my ( $users, $links ) = ( count('users'), count('links') );
    my $output = import_polr( '--from', $polr_url, '--dry-run' );
    like( $output, qr/^Links: 7 created, 1 already in Lembas, 3 without a user$/m, 'what would be imported' );
    like( $output, qr/^Dry run: nothing was written$/m,                            'says so' );
    is( count('users'), $users, 'no user written' );
    is( count('links'), $links, 'no link written' );
};

subtest 'import' => sub {
    plan tests => 23;
    my $output = import_polr( '--from', $polr_url );
    is(
        $output,
        join(
            "\n",
            'Endings in Polr: utf8mb3_unicode_ci, case insensitive: in Lembas they are case sensitive',
            'Users: 4 created, 1 already in Lembas',
            'Polr admins, to add to LEMBAS_ADMIN_EMAILS: admin@example.org',
            'API keys: 1 imported',
            'API keys left out: gone@example.org (disabled)',
            'API keys left out: someone@other.org (not example.org)',
            'Links: 7 created, 1 already in Lembas, 3 without a user',
            'Links too long to import: huge',
            'Secret links, now public: secret',
            'Clicks: 2',
            q{}
        ),
        'the summary'
    );

    my $admin = $db->select( users => '*', { email => 'admin@example.org' } )->hash;
    is( $admin->{polr_username}, 'admin',               'users are matched by email, in lower case' );
    is( $admin->{created_at},    '2017-01-02 03:04:05', 'with the date of their account' );
    is( $admin->{last_login_at}, undef,                 'never signed in to Lembas' );
    ok( !$db->select( users => 'is_active', { email => 'gone@example.org' } )->array->[0], 'disabled stays disabled' );
    is(
        $db->select( users => 'name', { email => 'jane@example.org' } )->array->[0], 'Jane',
        'a user of Lembas is left alone'
    );

    my $link = $t->app->links->find_by_ending('3Fz');
    is( $link->{long_url},   'https://example.org/docs', 'the ending and the long URL' );
    is( $link->{user_id},    $admin->{id},               'the creator' );
    is( $link->{clicks},     5,                          'the counter' );
    is( $link->{created_at}, '2017-05-06T07:08:09Z',     'the dates' );
    is( $link->{updated_at}, '2018-01-01T00:00:00Z',     'both' );
    my $custom = $t->app->links->find_by_ending('custom');
    ok( $custom->{is_custom} && $custom->{is_disabled} && $custom->{is_api}, 'the flags' );
    is( $custom->{user_id}, $jane->{id}, 'the creator, already a user of Lembas' );
    ok( !$t->app->links->find_by_ending('secret')->{is_disabled}, 'a secret link is a link' );
    is_deeply(
        [ map { $t->app->links->find_by_ending($_)->{user_id} } qw(anon anonapi ghost) ],
        [ undef, undef, undef ], 'anonymous links have no user'
    );
    is( $t->app->links->find_by_ending('huge'), undef, 'too long for Lembas' );
    is(
        $t->app->links->find_by_ending('taken')->{long_url}, 'https://example.org/already',
        'a link of Lembas is left alone'
    );
    is(
        $t->app->links->find_duplicate( $admin->{id}, "https://example.org/caf\x{e9}" )->{ending},
        'cafe', 'any character, found again when it is shortened again'
    );

    my $clicks = $db->select( clicks => '*', { link_id => $link->{id} }, 'id' )->hashes;
    is( scalar @$clicks, 2, 'the clicks' );
    is_deeply(
        [ @{ $clicks->[0] }{qw(clicked_at referer referer_host)} ],
        [ '2017-06-01 10:00:00', 'https://chat.example/room', 'chat.example' ],
        'their time and referer'
    );
    is( length $clicks->[0]{user_agent}, 512, 'their user agent, cut to the size of the column' );
    ok( !exists $clicks->[0]{ip}, 'never their address' );

    is( $t->app->api_keys->authenticate($admin_key), $admin->{id}, 'the API key of Polr works with Lembas' );
};

subtest 'again' => sub {
    plan tests => 3;
    my $output = import_polr( '--from', $polr_url );
    like( $output, qr/^Users: 0 created, 5 already in Lembas$/m,                   'no new user' );
    like( $output, qr/^Links: 0 created, 8 already in Lembas, 0 without a user$/m, 'no new link' );
    my $line = 'API keys left out: admin@example.org (already imported)';
    like( $output, qr/^\Q$line\E$/m, 'no key twice' );
};

subtest 'password file, case sensitive endings' => sub {
    plan tests => 4;
    my $other_url = Mojo::URL->new( create_database( 'polr_bin', 't/fixtures/polr_schema.sql' ) );
    my $other     = Mojo::mysql->new( $other_url->to_unsafe_string )->db;
    $other->query('ALTER TABLE links MODIFY short_url VARCHAR(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL');
    $other->insert( links =>
            { short_url => 'Other', long_url => 'https://example.org/o', ip => q{}, creator => q{}, secret_key => q{} }
    );

    my ( $user, $password ) = split /:/, $other_url->userinfo;
    my $dir    = tempdir;
    my $file   = $dir->child('password')->spew("$password\n");
    my $output = import_polr( '--from', $other_url->userinfo($user)->to_unsafe_string, '--password-file', "$file" );
    like( $output, qr/^Endings in Polr: utf8mb3_bin$/m, 'case sensitive like Lembas' );
    like( $output, qr/^Links: 1 created/m,              'connected with the password of the file' );
    unlike( $output, qr/Polr admins|too long|Secret links/, 'nothing else to say' );
    ok( $t->app->links->find_by_ending('Other'), 'imported' );
};

subtest 'usage' => sub {
    plan tests => 2;
    local $SIG{__WARN__} = sub { };    # Getopt::Long warns about the option
    like( ( eval { import_polr(); 1 } ? q{} : $@ ), qr/Usage: script\/lembas import_polr/, 'the source is needed' );
    like( ( eval { import_polr('--unknown'); 1 } ? q{} : $@ ), qr/Usage:/,                 'no unknown option' );
};
