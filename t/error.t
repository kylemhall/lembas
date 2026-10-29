use Mojo::Base -strict, -signatures;

use Test::More tests => 3;
use Test::NoWarnings;
use Mojo::Exception;
use Lembas::Error;

subtest 'throw() tests' => sub {
    plan tests => 4;
    my $error =
        eval { Lembas::Error->throw( code => 'taken', message => 'Taken', status => 409, detail => 'why' ); 1 }
        ? undef
        : $@;
    isa_ok( $error, 'Lembas::Error', 'what dies' );
    is( $error->code,    'taken', 'code' );
    is( $error->message, 'Taken', 'message' );
    is_deeply( [ $error->status, $error->detail ], [ 409, 'why' ], 'status and detail' );
};

subtest 'caught() tests' => sub {
    plan tests => 3;
    ok( Lembas::Error->caught( Lembas::Error->new ),                       'a Lembas::Error' );
    ok( !Lembas::Error->caught("Something broke\n"),                       'not a string' );
    ok( !Lembas::Error->caught( Mojo::Exception->new('Something broke') ), 'not another exception' );
};
