use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_link create_user reset_db test_app);
use Test::NoWarnings;
use Test::MockModule;
use Lembas::Model::Endings;

plan tests => 11;

my $t     = test_app( LEMBAS_SHORT_URL => 'https://short.example' );
my $links = $t->app->links;

# The Lembas::Error thrown by the code, or undef
sub error_of ($code) {
    return eval { $code->(); 1 } ? undef : $@;
}

subtest 'random endings' => sub {
    plan tests => 7;
    reset_db($t);
    my $user = create_user($t);
    my ( $link, $created ) = $links->create( { long_url => 'https://example.org/page', user_id => $user->{id} } );
    ok( $created, 'a new link' );
    like( $link->{ending}, qr/\A[A-Za-z0-9]{6}\z/, 'with a random ending of LEMBAS_ENDING_LENGTH' );
    is( $link->{short_url},     "https://short.example/$link->{ending}", 'its short URL' );
    is( $link->{long_url},      'https://example.org/page',              'its long URL' );
    is( $link->{creator_email}, $user->{email},                          'its creator' );
    ok( !$link->{is_custom} && !$link->{is_api} && !$link->{is_disabled}, 'not custom, not from the API, enabled' );
    is( $link->{clicks}, 0, 'no clicks' );
};

subtest 'duplicates' => sub {
    plan tests => 6;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    my $url = 'https://example.org/same';
    my ($link) = $links->create( { long_url => $url, user_id => $jane->{id} } );
    my ( $again, $created ) = $links->create( { long_url => $url, user_id => $jane->{id} } );
    is( $again->{id}, $link->{id}, 'the same user gets the same link' );
    ok( !$created, 'which is not new' );
    isnt( ( $links->create( { long_url => $url, user_id => $john->{id} } ) )[0]{id}, $link->{id}, 'not another user' );

    my ($custom) =
        $links->create( { long_url => 'https://example.org/custom', user_id => $jane->{id}, ending => 'mine' } );
    isnt(
        ( $links->create( { long_url => 'https://example.org/custom', user_id => $jane->{id} } ) )[0]{id},
        $custom->{id}, 'a custom link is not reused'
    );

    $links->update( $link->{id}, { is_disabled => 1 } );
    isnt(
        ( $links->create( { long_url => $url, user_id => $jane->{id} } ) )[0]{id}, $link->{id},
        'nor a disabled one'
    );
    ok(
        ( $links->create( { long_url => 'https://example.org/api', user_id => $jane->{id}, is_api => 1 } ) )[0]{is_api},
        'links can come from the API'
    );
};

subtest 'custom endings' => sub {
    plan tests => 9;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    my ( $link, $created ) =
        $links->create( { long_url => 'https://example.org/', user_id => $user_id, ending => 'Docs' } );
    ok( $created, 'created' );
    is( $link->{ending}, 'Docs', 'with its ending' );
    ok( $link->{is_custom}, 'custom' );
    ok(
        ( $links->create( { long_url => 'https://example.org/', user_id => $user_id, ending => 'docs' } ) )[0],
        'endings are case sensitive'
    );

    my $taken = error_of(
        sub { $links->create( { long_url => 'https://example.org/', user_id => $user_id, ending => 'Docs' } ) } );
    is_deeply( [ $taken->code, $taken->status ], [ 'ending_taken', 409 ], 'taken' );

    my $invalid = error_of(
        sub { $links->create( { long_url => 'https://example.org/', user_id => $user_id, ending => 'a b' } ) } );
    is_deeply( [ $invalid->code, $invalid->status ], [ 'invalid_ending', 400 ], 'invalid' );

    my $reserved = error_of(
        sub { $links->create( { long_url => 'https://example.org/', user_id => $user_id, ending => 'API' } ) } );
    is_deeply( [ $reserved->code, $reserved->status ], [ 'reserved_ending', 400 ], 'reserved' );
    like( $reserved->message, qr/"API" is reserved/, 'says which' );
    is( $links->find_by_ending('API'), undef, 'nothing was created' );
};

subtest 'long URLs' => sub {
    my %invalid = (
        'not http'  => 'ftp://example.org/file',
        'relative'  => 'example.org/page',
        'no host'   => 'https:page',
        'too long'  => 'https://example.org/' . ( 'x' x 8200 ),
        'no scheme' => '//example.org/page',
    );
    plan tests => 3 + keys %invalid;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    for my $case ( sort keys %invalid ) {
        my $error = error_of( sub { $links->create( { long_url => $invalid{$case}, user_id => $user_id } ) } );
        is( $error->code, 'invalid_url', "invalid: $case" );
    }
    ok(
        ( $links->create( { long_url => 'HTTPS://example.org/', user_id => $user_id } ) )[0],
        'the scheme in capitals'
    );
    my $unicode = "https://example.org/caf\x{e9}";
    is( ( $links->create( { long_url => $unicode, user_id => $user_id } ) )[0]{long_url}, $unicode, 'any character' );
    ok(
        ( $links->create( { long_url => 'https://example.org/' . ( 'x' x 8172 ), user_id => $user_id } ) )[0],
        'the longest URL'
    );
};

subtest 'collisions' => sub {
    plan tests => 5;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    create_link( $t, ending => 'taken1', user_id => $user_id );

    my @endings  = qw(taken1 health free01);
    my $sequence = Lembas::Model::Endings->new( generator => sub (@) { return shift @endings } );
    my $retrying =
        Lembas::Model::Links->new( mysql => $t->app->mysql, short_url => 'https://s/', endings => $sequence );
    my ($link) = $retrying->create( { long_url => 'https://example.org/a', user_id => $user_id } );
    is( $link->{ending}, 'free01', 'a taken ending and a reserved word are skipped' );

    my $always  = Lembas::Model::Endings->new( generator => sub (@) { return 'taken1' } );
    my $failing = Lembas::Model::Links->new(
        mysql        => $t->app->mysql,
        short_url    => 'https://s/',
        endings      => $always,
        max_attempts => 2
    );
    my $error = error_of( sub { $failing->create( { long_url => 'https://example.org/b', user_id => $user_id } ) } );
    is_deeply( [ $error->code, $error->status ], [ 'no_free_ending', 500 ], 'gives up after max_attempts' );

    my $database = Test::MockModule->new('Mojo::mysql::Database');
    $database->redefine( insert => sub (@) { die "Lost connection to the server\n" } );
    is(
        error_of( sub { $links->create( { long_url => 'https://example.org/c', user_id => $user_id } ) } ),
        "Lost connection to the server\n", 'other database errors are not retried'
    );
    $database->unmock('insert');

    is( Lembas::Model::Links->new->max_attempts, 5, 'five attempts by default' );
    isa_ok( Lembas::Model::Links->new->endings, 'Lembas::Model::Endings', 'the default endings' );
};

subtest 'find() and find_by_ending() tests' => sub {
    plan tests => 5;
    reset_db($t);
    my $row = create_link( $t, ending => 'abc' );
    is( $links->find( $row->{id} )->{ending},           'abc',      'by id' );
    is( $links->find_by_ending('abc')->{id},            $row->{id}, 'by ending' );
    is( $links->find_by_ending('ABC'),                  undef,      'case sensitive' );
    is( $links->find( $row->{id} + 1000 ),              undef,      'no such id' );
    is( create_link( $t, user_id => undef )->{user_id}, undef,      'links imported from Polr may have no user' );
};

subtest 'list() tests' => sub {
    plan tests => 8;
    reset_db($t);
    my ( $jane, $john ) = ( create_user($t), create_user($t) );
    create_link( $t, ending => "jane$_", user_id => $jane->{id}, created_at => "2026-01-0$_ 00:00:00" ) for 1 .. 3;
    create_link( $t, ending => 'john1',  user_id => $john->{id}, long_url   => 'https://example.org/100%_sure' );

    my %page = ( page => 1, per_page => 2 );
    my $mine = $links->list( { %page, user_id => $jane->{id} } );
    is_deeply( [ map { $_->{ending} } @{ $mine->{links} } ], [qw(jane3 jane2)], 'newest first, one page' );
    is( $mine->{total}, 3, 'and the total' );
    is_deeply(
        [ map { $_->{ending} } @{ $links->list( { %page, page => 2, user_id => $jane->{id} } )->{links} } ],
        ['jane1'], 'the second page'
    );
    is( $links->list( { %page, all => 1 } )->{total}, 4, 'everybody\'s' );
    is_deeply(
        [ map { $_->{ending} } @{ $links->list( { %page, user_id => $jane->{id}, q => 'ne2' } )->{links} } ],
        ['jane2'], 'search in the endings'
    );
    is( $links->list( { %page, all     => 1, q => '100%_' } )->{total}, 1, 'and in the long URLs' );
    is( $links->list( { %page, all     => 1, q => '%' } )->{total},     1, 'LIKE wildcards are literal' );
    is( $links->list( { %page, user_id => $john->{id}, q => 'jane' } )->{total}, 0, 'only the links of the user' );
};

subtest 'update() tests' => sub {
    plan tests => 5;
    reset_db($t);
    my $user_id = create_user($t)->{id};
    my ($link) = $links->create( { long_url => 'https://example.org/old', user_id => $user_id } );
    is(
        $links->update( $link->{id}, { long_url => 'https://example.org/new' } )->{long_url},
        'https://example.org/new', 'a new long URL'
    );
    is(
        ( $links->create( { long_url => 'https://example.org/new', user_id => $user_id } ) )[0]{id},
        $link->{id}, 'which is found as a duplicate'
    );
    ok( $links->update( $link->{id},  { is_disabled => 1 } )->{is_disabled}, 'disabled' );
    ok( !$links->update( $link->{id}, { is_disabled => 0 } )->{is_disabled}, 'enabled' );
    is(
        error_of( sub { $links->update( $link->{id}, { long_url => 'nope' } ) } )->code, 'invalid_url',
        'the long URL is checked'
    );
};

subtest 'remove() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $row = create_link($t);
    is_deeply( [ $links->remove( $row->{id} ) ], [], 'returns nothing' );
    is( $links->find( $row->{id} ), undef, 'gone' );
};

subtest 'find_duplicate() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $row = create_link( $t, long_url => 'https://example.org/x' );
    is( $links->find_duplicate( $row->{user_id}, 'https://example.org/x' )->{id}, $row->{id}, 'found' );
    is( $links->find_duplicate( $row->{user_id}, 'https://example.org/y' ),       undef,      'another URL' );
};
