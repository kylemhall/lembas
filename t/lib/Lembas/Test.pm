package Lembas::Test;
use Mojo::Base -strict, -signatures;

use parent qw(Exporter);
use Test::More;
use Test::Mojo;
use Mojo::mysql;
use Mojo::URL;
use Digest::SHA qw(sha256_hex);
use Encode      qw(encode_utf8);

our @EXPORT_OK = qw(capture_stdout create_click create_link create_user reset_db test_app);

# The environment of the test applications, with the database of the test process
use constant TEST_ENV => {
    LEMBAS_BASE_URL           => 'http://localhost',
    LEMBAS_SECRETS            => 'test-secret-0123456789',
    LEMBAS_OIDC_ISSUER        => 'http://oidc.invalid',
    LEMBAS_OIDC_CLIENT_ID     => 'lembas-test',
    LEMBAS_OIDC_CLIENT_SECRET => 'test-client-secret',
    LEMBAS_ALLOWED_DOMAIN     => 'example.org',
    LEMBAS_LOG_LEVEL          => 'fatal',
};

my ( $server, $database, $database_url, $created_by );
my $sequence = 0;

# Importing this module means the test needs a database: without one it is skipped, before Test::NoWarnings is loaded
sub import ( $class, @names ) {
    plan skip_all => 'Set TEST_ONLINE to a MariaDB server, like mariadb://root:root@mariadb/lembas_test'
        unless $ENV{TEST_ONLINE};
    $class->export_to_level( 1, $class, @names );
    return;
}

sub test_app (%env) {
    state $migrated = 0;
    my $t = Test::Mojo->new( Lembas => { env => { %{ TEST_ENV() }, LEMBAS_DB_URL => _database_url(), %env } } );
    $t->app->mysql->migrations->migrate unless $migrated++;
    return $t;
}

sub reset_db ($t) {
    my $db = $t->app->mysql->db;
    $db->query('SET FOREIGN_KEY_CHECKS = 0');
    $db->query("TRUNCATE TABLE `$_`") for grep { $_ ne 'mojo_migrations' } @{ $db->tables };
    $db->query('SET FOREIGN_KEY_CHECKS = 1');
    $t->reset_session;
    return;
}

# The fixtures are inserted as rows, not with the models: a bug in a model fails its own test, not every test
sub create_user ( $t, %columns ) {
    my $n  = ++$sequence;
    my $db = $t->app->mysql->db;
    my $id = $db->insert( users => { email => "user$n\@example.org", name => "User $n", %columns } )->last_insert_id;
    return $db->select( users => '*', { id => $id } )->hash;
}

sub create_link ( $t, %columns ) {
    my $n  = ++$sequence;
    my $db = $t->app->mysql->db;
    $columns{user_id} = create_user($t)->{id} unless exists $columns{user_id};
    my $long_url = $columns{long_url} // "https://example.org/$n";
    my $id =
        $db->insert( links =>
            { ending => "e$n", long_url => $long_url, long_url_hash => sha256_hex( encode_utf8($long_url) ), %columns }
        )->last_insert_id;
    return $db->select( links => '*', { id => $id } )->hash;
}

sub create_click ( $t, %columns ) {
    $columns{link_id} = create_link($t)->{id} unless exists $columns{link_id};
    my $db = $t->app->mysql->db;
    my $id = $db->insert( clicks => \%columns )->last_insert_id;
    return $db->select( clicks => '*', { id => $id } )->hash;
}

sub capture_stdout ($code) {
    open my $handle, '>', \my $output or die "Cannot capture the output: $!\n";
    local *STDOUT = $handle;
    $code->();
    close $handle or die "Cannot capture the output: $!\n";
    return $output;
}

# A database of its own for every test process, so that prove -j is safe
sub _database_url {
    return $database_url if $database_url;
    my $url = Mojo::URL->new( $ENV{TEST_ONLINE} );
    $database = sprintf '%s_%d', $url->path->parts->[0] // 'lembas_test', $$;

    # Mojo::mysql cannot connect without a database name
    $server = Mojo::mysql->new( $url->clone->path('/information_schema')->to_unsafe_string );
    $server->db->query("DROP DATABASE IF EXISTS `$database`");
    $server->db->query("CREATE DATABASE `$database`");
    $created_by = $$;
    return $database_url = $url->path("/$database")->to_unsafe_string;
}

END {
    local $? = $?;
    $server->db->query("DROP DATABASE IF EXISTS `$database`") if $created_by && $created_by == $$;
}

1;

=head1 NAME

Lembas::Test - Helpers for the tests that need a database

=head1 SYNOPSIS

  use Test::More;
  use Lembas::Test qw(test_app reset_db);
  use Test::NoWarnings;

  plan tests => 2;
  my $t = test_app( LEMBAS_ADMIN_EMAILS => 'jane@example.org' );

=head1 DESCRIPTION

C<TEST_ONLINE> names a MariaDB server, and the user must be allowed to create databases. Every test process gets a
database of its own, migrated to the latest version and dropped at the end.

=head2 test_app

A L<Test::Mojo> for a new Lembas application, the given variables added to its environment.

=head2 reset_db

Empties every table and forgets the session cookie.

=head2 create_user

Inserts a user, the given columns over the defaults, and returns its row.

=head2 create_link

Inserts a link, for a new user unless C<user_id> is given, and returns its row.

=head2 create_click

Inserts a click, on a new link unless C<link_id> is given, and returns its row. The counter of the link is not changed.

=head2 capture_stdout

Runs the code and returns what it printed.

=cut
