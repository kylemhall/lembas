use Mojo::Base -strict, -signatures;

use Test::More tests => 5;
use Test::NoWarnings;
use Mojo::File qw(path);
use Test::Mojo;
use Lembas::Model::Endings;

my $endings = Lembas::Model::Endings->new;

subtest 'is_valid() tests' => sub {
    my @valid   = ( 'a', 'Az09_-', 'x' x 64 );
    my @invalid = ( q{}, 'x' x 65, 'with space', "caf\x{e9}", 'a/b', "line\n", 'a.b' );
    plan tests => @valid + @invalid;
    ok( $endings->is_valid($_),  "valid: $_" )   for @valid;
    ok( !$endings->is_valid($_), "invalid: $_" ) for @invalid;
};

subtest 'is_reserved() tests' => sub {
    plan tests => 6;
    ok( $endings->is_reserved('api'),         'api' );
    ok( $endings->is_reserved('API'),         'whatever the case' );
    ok( $endings->is_reserved('Health'),      'health' );
    ok( $endings->is_reserved('favicon.ico'), 'a static file' );
    ok( !$endings->is_reserved('apis'),       'not a prefix' );
    ok( !$endings->is_reserved('abc123'),     'any other ending' );
};

subtest 'random() tests' => sub {
    plan tests => 4;
    like( $endings->random(6), qr/\A[A-Za-z0-9]{6}\z/, 'letters and digits, of the given length' );
    my %seen = map { $endings->random(8) => 1 } 1 .. 100;
    is( scalar keys %seen, 100, 'random' );

    my @arguments;
    my $fixed = Lembas::Model::Endings->new( generator => sub (@given) { @arguments = @given; return 'fixed' } );
    is( $fixed->random(5), 'fixed', 'from the generator' );
    is_deeply( \@arguments, [ Lembas::Model::Endings::ALPHABET, 5 ], 'given the alphabet and the length' );
};

subtest 'every route is reserved' => sub {
    my $app = Test::Mojo->new(
        Lembas => {
            env => {
                LEMBAS_BASE_URL           => 'https://lembas.example.org',
                LEMBAS_DB_URL             => 'mariadb://lembas@db/lembas',
                LEMBAS_SECRETS            => 'test-secret-0123456789',
                LEMBAS_OIDC_CLIENT_ID     => 'client-id',
                LEMBAS_OIDC_CLIENT_SECRET => 'client-secret',
                LEMBAS_ALLOWED_DOMAIN     => 'example.org',
            }
        }
    )->app;

    my @segments = map { $_->basename } path('public')->list( { dir => 1 } )->each;
    my @routes   = @{ $app->routes->children };
    while ( my $route = shift @routes ) {
        my ($segment) = $route->pattern->unparsed =~ m{\A/([^/:*<]+)};
        if ( defined $segment ) {
            push @segments, $segment;
        } else {
            push @routes, @{ $route->children };
        }
    }
    plan tests => scalar @segments;
    ok( $endings->is_reserved($_), "/$_ is reserved" ) for @segments;
};
