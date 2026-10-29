use Mojo::Base -strict, -signatures;

use Test::More tests => 3;
use Test::NoWarnings;
use Mojo::Server;

my $app = Mojo::Server->new->load_app('script/lembas');
isa_ok( $app, 'Lembas', 'script/lembas' );
ok( ( grep { $_ eq 'Lembas::Command' } @{ $app->commands->namespaces } ), 'the commands of Lembas are found' );
