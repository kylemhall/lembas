use Mojo::Base -strict, -signatures;

# all_pod_files_ok plans the tests itself: no Test::NoWarnings here

use Test::More;
use Test::Pod;

all_pod_files_ok( all_pod_files(qw(lib script)) );
