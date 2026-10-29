use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_click create_link reset_db test_app);
use Test::NoWarnings;

plan tests => 4;

my $t      = test_app();
my $clicks = $t->app->clicks;
my $db     = $t->app->mysql->db;

subtest 'add() tests' => sub {
    plan tests => 6;
    reset_db($t);
    my $link = create_link($t);
    is_deeply(
        [ $clicks->add( $link->{id}, { referer => 'https://www.example.org/page?x=1', user_agent => 'Browser/1.0' } ) ],
        [], 'returns nothing'
    );
    $clicks->add( $link->{id}, {} );
    my $rows = $db->select( clicks => [qw(referer referer_host user_agent)], { link_id => $link->{id} }, 'id' )->hashes;
    is_deeply(
        $rows->[0],
        {
            referer    => 'https://www.example.org/page?x=1', referer_host => 'www.example.org',
            user_agent => 'Browser/1.0'
        },
        'the referer, its host and the user agent'
    );
    is_deeply( $rows->[1], { referer => undef, referer_host => undef, user_agent => undef }, 'a direct visit' );
    is( $db->select( links => 'clicks', { id => $link->{id} } )->array->[0], 2, 'the counter of the link' );

    $clicks->add( $link->{id}, { referer => 'https://example.org/' . ( 'x' x 3000 ), user_agent => 'y' x 600 } );
    my $long = $db->select( clicks => [qw(referer user_agent)], { link_id => $link->{id} }, { -desc => 'id' } )->hash;
    is_deeply(
        [ length $long->{referer}, length $long->{user_agent} ], [ 2048, 512 ],
        'cut to the size of the columns'
    );

    $clicks->add( $link->{id}, { referer => 'not a URL' } );
    is(
        $db->select( clicks => 'referer_host', { link_id => $link->{id} }, { -desc => 'id' } )->array->[0], undef,
        'no host for a referer that is not a URL'
    );
};

subtest 'stats() tests' => sub {
    plan tests => 3;
    reset_db($t);
    my $link = create_link($t);
    my %at   = ( link_id => $link->{id} );
    create_click( $t, %at, clicked_at => '2026-09-30 23:59:59', referer_host => 'before.example' );
    create_click( $t, %at, clicked_at => '2026-10-01 00:00:00', referer_host => 'a.example' );
    create_click( $t, %at, clicked_at => '2026-10-01 12:00:00', referer_host => 'b.example' );
    create_click( $t, %at, clicked_at => '2026-10-03 08:00:00', referer_host => 'b.example' );
    create_click( $t, %at, clicked_at => '2026-10-03 23:59:59' );
    create_click( $t, %at, clicked_at => '2026-10-04 00:00:00', referer_host => 'after.example' );
    create_click( $t, clicked_at => '2026-10-02 00:00:00' );

    my $stats = $clicks->stats( $link->{id}, '2026-10-01', '2026-10-03' );
    is( $stats->{total}, 4, 'the clicks of the period, both days included' );
    is_deeply(
        $stats->{clicks_per_day},
        [ { day => '2026-10-01', clicks => 2 }, { day => '2026-10-03', clicks => 2 } ],
        'per day, the days without clicks left out'
    );
    is_deeply(
        $stats->{top_referers},
        [ { host => 'b.example', clicks => 2 }, { host => q{}, clicks => 1 }, { host => 'a.example', clicks => 1 } ],
        'the referers, the most frequent first; an empty host is a direct visit'
    );
};

subtest 'top ten' => sub {
    plan tests => 2;
    reset_db($t);
    my $link = create_link($t);
    create_click( $t, link_id => $link->{id}, clicked_at => '2026-10-01 10:00:00', referer_host => "host$_.example" )
        for 1 .. 12;
    my $stats = $clicks->stats( $link->{id}, '2026-10-01', '2026-10-01' );
    is( scalar @{ $stats->{top_referers} }, 10, 'ten referers at most' );
    is( $stats->{total},                    12, 'every click counts' );
};
