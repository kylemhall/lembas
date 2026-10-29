use Mojo::Base -strict, -signatures;

# all_critic_ok plans the tests itself: no Test::NoWarnings here

use Test::More;
use Test::Perl::Critic ( -profile => '.perlcriticrc' );

all_critic_ok(qw(lib script t));
