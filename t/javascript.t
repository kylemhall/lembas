use Mojo::Base -strict, -signatures;

# The JavaScript of public/js is tested by t/js/*.test.js with the test runner of Node: no build, no dependency

use Test::More tests => 3;
use Test::NoWarnings;

open my $node, '-|', 'node', '--test', '--experimental-test-coverage', 't/js/' or die "Cannot run node: $!\n";
my @output = <$node>;
close $node;
is( $?, 0, 'the JavaScript tests pass' ) or diag @output;

my ($coverage) = grep { m{\A# public/js/app\.js\s*\|} } @output;
like(
    $coverage // q{},
    qr/\|\s*100\.00\s*\|\s*100\.00\s*\|\s*100\.00\s*\|/,
    'every line, branch and function of public/js/app.js is covered'
) or diag @output;
