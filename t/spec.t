use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(test_app);
use Test::NoWarnings;
use Mojo::Loader qw(load_class);
use JSON::Validator;
use Lembas;

plan tests => 4;

my $t = test_app();

subtest 'the specification is valid' => sub {
    plan tests => 1;
    my $schema = JSON::Validator->new->schema('api/lembas.yaml')->schema;
    is_deeply( [ map { "$_" } @{ $schema->errors } ], [], 'no errors' );
};

subtest 'it is served' => sub {
    plan tests => 4;
    $t->get_ok('/api/v1')
        ->status_is(200)
        ->json_is( '/info/title'   => 'Lembas' )
        ->json_is( '/info/version' => $Lembas::VERSION );
};

subtest 'every operation has a controller' => sub {
    my $spec       = JSON::Validator->new->schema('api/lembas.yaml')->schema->data;
    my @operations = map { values %{ $spec->{paths}{$_} } } keys %{ $spec->{paths} };
    plan tests => 2 * @operations;
    for my $operation (@operations) {
        my ( $name, $action ) = split /#/, $operation->{'x-mojo-to'};
        my $class = 'Lembas::Controller::' . join q{}, map { ucfirst } split /_/, $name;
        ok( !load_class($class),  "$class exists" );
        ok( $class->can($action), "$operation->{operationId}: $class has $action" );
    }
};
