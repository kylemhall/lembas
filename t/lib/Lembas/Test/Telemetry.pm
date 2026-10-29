package Lembas::Test::Telemetry;
use Mojo::Base -strict, -signatures;

use parent qw(Exporter);
use OpenTelemetry;
use OpenTelemetry::Propagator::TraceContext;
use OpenTelemetry::SDK::Logs::LogRecord::Processor::Simple;
use OpenTelemetry::SDK::Logs::LoggerProvider;
use OpenTelemetry::SDK::Trace::Span::Processor::Simple;
use OpenTelemetry::SDK::Trace::TracerProvider;
use Lembas::Test::Exporter;

our @EXPORT_OK = qw(log_records spans start_in_memory);

my $span_exporter = Lembas::Test::Exporter->new;
my $log_exporter  = Lembas::Test::Exporter->new;

# An sdk_starter for Lembas::Telemetry: the providers of the SDK, exporting at once to memory
sub start_in_memory (@) {
    my $tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider->new;
    $tracer_provider->add_span_processor(
        OpenTelemetry::SDK::Trace::Span::Processor::Simple->new( exporter => $span_exporter ) );
    OpenTelemetry->tracer_provider = $tracer_provider;

    my $logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider->new;
    $logger_provider->add_log_record_processor(
        OpenTelemetry::SDK::Logs::LogRecord::Processor::Simple->new( exporter => $log_exporter ) );
    OpenTelemetry->logger_provider = $logger_provider;

    OpenTelemetry->propagator = OpenTelemetry::Propagator::TraceContext->new;
    return;
}

sub spans ()       { return [ splice @{ $span_exporter->exported } ] }
sub log_records () { return [ splice @{ $log_exporter->exported } ] }

1;

=head1 NAME

Lembas::Test::Telemetry - OpenTelemetry for the tests

=head1 SYNOPSIS

  $t->app->telemetry->sdk_starter( \&start_in_memory );
  $t->get_ok('/');
  my ($span) = @{ spans() };

=head1 DESCRIPTION

=head2 start_in_memory

Installs SDK providers whose spans and log records are exported to memory, at once.

=head2 spans

The spans exported since the last call.

=head2 log_records

The log records exported since the last call.

=cut
