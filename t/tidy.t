use Mojo::Base -strict, -signatures;

use Test::More tests => 2;
use Test::NoWarnings;

is( system( $^X, 'script/tidy', '--check' ), 0, 'every file is tidy (fix with script/tidy)' );
