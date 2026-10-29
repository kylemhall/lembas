use Mojo::Base -strict, -signatures;

use Test::More tests => 9;
use Test::NoWarnings;
use Test::MockModule;
use Mojo::File qw(tempdir);
use Mojo::IOLoop;
use OpenTelemetry::Constants qw(EXPORT_RESULT_FAILURE EXPORT_RESULT_SUCCESS);
use OpenTelemetry::SDK::Trace::TracerProvider;
use Lembas::Telemetry::Processor;
use Lembas::Test::Exporter;

sub processor (%attributes) {
    return Lembas::Telemetry::Processor->new( exporter => Lembas::Test::Exporter->new, %attributes );
}

sub span () {
    return OpenTelemetry::SDK::Trace::TracerProvider->new->tracer( name => 'test' )->create_span( name => 'a span' );
}

# Runs the loop until the child process of the export is done
sub wait_for ($subprocess) {
    Mojo::IOLoop->one_tick until defined $subprocess->exit_code;
    return;
}

subtest 'DOES() tests' => sub {
    plan tests => 5;
    my $processor = processor();
    ok( $processor->DOES('OpenTelemetry::Trace::Span::Processor'),     'a span processor' );
    ok( $processor->DOES('OpenTelemetry::Logs::LogRecord::Processor'), 'a log record processor' );
    ok( $processor->DOES('OpenTelemetry::Processor'),                  'a processor' );
    ok( $processor->DOES('Mojo::Base'),                                'and what it inherits' );
    ok( !$processor->DOES('OpenTelemetry::Exporter'),                  'not anything else' );
};

subtest 'on_start() and on_end() tests' => sub {
    plan tests => 4;
    my $processor = processor();
    is_deeply( [ $processor->on_start( span(), undef ) ], [], 'nothing on start' );
    $processor->on_end( span() );
    is( scalar @{ $processor->queue }, 1, 'a sampled span is queued' );
    isa_ok( $processor->queue->[0], 'OpenTelemetry::SDK::Trace::Span::Readable', 'its snapshot' );

    my $flags = Test::MockModule->new('OpenTelemetry::Propagator::TraceContext::TraceFlags');
    $flags->redefine( sampled => 0 );
    $processor->on_end( span() );
    is( scalar @{ $processor->queue }, 1, 'a span that is not sampled is not' );
};

subtest 'on_emit() tests' => sub {
    plan tests => 1;
    my $processor = processor();
    $processor->on_emit( { body => 'a log record' } );
    is_deeply( $processor->queue, [ { body => 'a log record' } ], 'queued' );
};

subtest 'process() tests' => sub {
    plan tests => 3;
    my $exports = 0;
    my $mock    = Test::MockModule->new('Lembas::Telemetry::Processor');
    $mock->redefine( export_queue => sub ($self) { $exports++; return } );

    my $processor = processor( max_queue_size => 3, batch_size => 10 );
    $processor->process( 1 .. 5 );
    is_deeply( $processor->queue, [ 3, 4, 5 ], 'the oldest are dropped when the queue is full' );
    is( $exports, 0, 'not a batch yet' );

    processor( batch_size => 2 )->process( 1, 2 );
    is( $exports, 1, 'exported once there is a batch' );
};

subtest 'export_queue() tests' => sub {
    plan tests => 7;
    my @warnings;
    local $SIG{__WARN__} = sub ($warning) { push @warnings, $warning };
    my $dir = tempdir;

    ok( !defined processor()->export_queue, 'nothing to export, no child process' );

    my $processor = processor( exporter => Lembas::Test::Exporter->new( file => "$dir/exported" ) );
    $processor->process( 1 .. 3 );
    wait_for( $processor->export_queue );
    is( $dir->child('exported')->slurp, 3, 'exported in a child process' );
    is_deeply( $processor->queue, [], 'the queue is empty' );
    is_deeply( \@warnings,        [], 'no warning' );

    my $failing = processor( exporter => Lembas::Test::Exporter->new( result => EXPORT_RESULT_FAILURE ) );
    $failing->process(1);
    wait_for( $failing->export_queue );
    like(
        shift @warnings, qr/\AOpenTelemetry export failed: result \Q${\ EXPORT_RESULT_FAILURE }\E\n\z/,
        'a failed export'
    );

    my $dying = processor( exporter => Lembas::Test::Exporter->new( fails => 1 ) );
    $dying->process(1);
    wait_for( $dying->export_queue );
    like( shift @warnings, qr/\AOpenTelemetry export failed: The exporter fails/, 'an exporter that dies' );
    is_deeply( \@warnings, [], 'nothing else' );
};

subtest 'export_batch() tests' => sub {
    plan tests => 2;
    my $processor = processor( timeout => 3 );
    is( $processor->export_batch( [ 1, 2 ] ), EXPORT_RESULT_SUCCESS, 'the result of the exporter' );
    is_deeply( $processor->exporter->exported, [ 1, 2 ], 'exported in this process' );
};

subtest 'force_flush() tests' => sub {
    plan tests => 4;
    my $processor = processor();
    is( $processor->force_flush->get, EXPORT_RESULT_SUCCESS, 'nothing to export' );
    $processor->process( 1, 2 );
    is( $processor->force_flush->get, EXPORT_RESULT_SUCCESS, 'exported' );
    is_deeply( $processor->exporter->exported, [ 1, 2 ], 'in this process' );
    is_deeply( $processor->queue,              [],       'the queue is empty' );
};

subtest 'shutdown() tests' => sub {
    plan tests => 2;
    my $processor = processor();
    $processor->process(1);
    is( $processor->shutdown->get, EXPORT_RESULT_SUCCESS, 'like a flush' );
    is_deeply( $processor->exporter->exported, [1], 'what was queued is exported' );
};
