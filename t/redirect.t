use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_link reset_db test_app);
use Test::NoWarnings;
use Test::MockModule;

plan tests => 7;

my $t  = test_app();
my $db = $t->app->mysql->db;

subtest 'a link' => sub {
    plan tests => 9;
    reset_db($t);
    my $link = create_link( $t, ending => 'Docs', long_url => 'https://example.org/docs?page=2#top' );
    $t->get_ok( '/Docs' => { Referer => 'https://chat.example/room', 'User-Agent' => 'Browser/2.0' } )
        ->status_is(302)
        ->header_is( Location        => 'https://example.org/docs?page=2#top' )
        ->header_is( 'Cache-Control' => 'private, no-store', 'never cached by browsers' );
    is( $db->select( links => 'clicks', { id => $link->{id} } )->array->[0], 1, 'the click is counted' );
    is_deeply(
        $db->select( clicks => [qw(referer referer_host user_agent)], { link_id => $link->{id} } )->hash,
        { referer => 'https://chat.example/room', referer_host => 'chat.example', user_agent => 'Browser/2.0' },
        'and recorded'
    );
    $t->head_ok('/Docs')->status_is(302);
    is( $db->select( links => 'clicks', { id => $link->{id} } )->array->[0], 1, 'a HEAD request is not a click' );
};

subtest 'case sensitive' => sub {
    plan tests => 4;
    reset_db($t);
    create_link( $t, ending => 'abc', long_url => 'https://example.org/lower' );
    create_link( $t, ending => 'ABC', long_url => 'https://example.org/upper' );
    $t->get_ok('/abc')->header_is( Location => 'https://example.org/lower' );
    $t->get_ok('/ABC')->header_is( Location => 'https://example.org/upper' );
};

subtest 'unknown' => sub {
    plan tests => 3;
    reset_db($t);
    $t->get_ok('/nothing')->status_is(404)->text_is( h1 => 'Nothing here' );
};

subtest 'disabled' => sub {
    plan tests => 4;
    reset_db($t);
    my $link = create_link( $t, ending => 'off', is_disabled => 1 );
    $t->get_ok('/off')->status_is(410)->text_is( h1 => 'This link is disabled' );
    is( $db->select( clicks => 'count(*)', { link_id => $link->{id} } )->array->[0], 0, 'no click recorded' );
};

subtest 'not an ending' => sub {
    plan tests => 3;
    my $searches = 0;
    my $links    = Test::MockModule->new('Lembas::Model::Links');
    $links->redefine( find_by_ending => sub (@) { $searches++; return } );
    $t->get_ok('/not.an.ending')->status_is(404);
    is( $searches, 0, 'the database is not even asked' );
};

subtest 'the click cannot be recorded' => sub {
    plan tests => 4;
    reset_db($t);
    create_link( $t, ending => 'up', long_url => 'https://example.org/' );
    my @errors;
    $t->app->log->level('error')
        ->unsubscribe('message')
        ->on( message => sub ( $, $, @lines ) { push @errors, "@lines" } );
    my $clicks = Test::MockModule->new('Lembas::Model::Clicks');
    $clicks->redefine( add => sub (@) { die "The database is read only\n" } );
    $t->get_ok('/up')->status_is(302)->header_is( Location => 'https://example.org/', 'the redirect happens anyway' );
    like( "@errors", qr/Could not record a click on up: The database is read only/, 'the error is logged' );
};
