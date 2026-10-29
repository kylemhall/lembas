use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(create_link create_user reset_db test_app);
use Test::NoWarnings;

plan tests => 7;

my $t     = test_app( LEMBAS_ADMIN_EMAILS => 'admin@example.org' );
my $users = $t->app->users;

subtest 'find() tests' => sub {
    plan tests => 5;
    reset_db($t);
    my $row  = create_user( $t, email => 'jane@example.org', name => 'Jane Doe' );
    my $user = $users->find( $row->{id} );
    is_deeply(
        [ @$user{qw(id email name)} ],
        [ $row->{id}, 'jane@example.org', 'Jane Doe' ],
        'id, email and name'
    );
    ok( $user->{is_active}, 'active' );
    ok( !$user->{is_admin}, 'not an admin' );
    like( $user->{created_at}, qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, 'dates in ISO 8601, UTC' );
    is( $users->find( $row->{id} + 1000 ), undef, 'nobody' );
};

subtest 'find_by_email() tests' => sub {
    plan tests => 4;
    reset_db($t);
    create_user( $t, email => 'admin@example.org', is_active => 0 );
    my $user = $users->find_by_email('Admin@Example.org');
    is( $user->{email}, 'admin@example.org', 'whatever the case' );
    ok( $user->{is_admin},   'an admin, from LEMBAS_ADMIN_EMAILS' );
    ok( !$user->{is_active}, 'disabled' );
    is( $users->find_by_email('nobody@example.org'), undef, 'nobody' );
};

subtest 'find_or_create_from_claims() tests' => sub {
    plan tests => 6;
    reset_db($t);
    my $user = $users->find_or_create_from_claims( { email => 'new@example.org', name => 'New', sub => 'sub-1' } );
    is( $user->{name}, 'New', 'created' );
    ok( defined $user->{last_login_at}, 'with the time of the sign-in' );

    my $again = $users->find_or_create_from_claims( { email => 'new@example.org', name => 'Renamed', sub => 'sub-1' } );
    is( $again->{id},   $user->{id}, 'the same user the next time' );
    is( $again->{name}, 'Renamed',   'with the name of the token' );

    $users->set_active( $user->{id}, 0 );
    ok(
        !$users->find_or_create_from_claims( { email => 'new@example.org', name => 'New', sub => 'sub-1' } )
            ->{is_active},
        'a disabled account stays disabled'
    );
    is(
        $t->app->mysql->db->select( users => 'google_sub', { id => $user->{id} } )->array->[0], 'sub-1',
        'the subject is kept'
    );
};

subtest 'list() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $bob = create_user( $t, email => 'bob@example.org' );
    create_user( $t, email => 'alice@example.org' );
    create_link( $t, user_id => $bob->{id} ) for 1 .. 2;
    my $list = $users->list;
    is_deeply( [ map { $_->{email} } @$list ],       [ 'alice@example.org', 'bob@example.org' ], 'by email' );
    is_deeply( [ map { $_->{links_count} } @$list ], [ 0,                   2 ], 'with the number of their links' );
};

subtest 'set_active() tests' => sub {
    plan tests => 4;
    reset_db($t);
    my $id = create_user($t)->{id};
    is( $users->set_active( $id, 0 ), 1, 'disabled' );
    ok( !$users->find($id)->{is_active}, 'inactive' );
    is( $users->set_active( $id,        1 ), 1, 'enabled again' );
    is( $users->set_active( $id + 1000, 0 ), 0, 'nobody to change' );
};

subtest 'create_imported() tests' => sub {
    plan tests => 2;
    reset_db($t);
    my $id = $users->create_imported(
        {
            email      => 'old@example.org', name => q{}, polr_username => 'old', is_active => 1,
            created_at => '2017-03-04 05:06:07'
        }
    );
    my $user = $users->find($id);
    is( $user->{polr_username}, 'old',                  'the Polr username is kept' );
    is( $user->{created_at},    '2017-03-04T05:06:07Z', 'and the date it was created' );
};
