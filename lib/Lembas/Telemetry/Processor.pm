package Lembas::Telemetry::Processor;
use Mojo::Base -base, -signatures;

use Future;
use Mojo::IOLoop;
use OpenTelemetry::Constants qw(EXPORT_RESULT_SUCCESS);

use constant ROLES => { map { $_ => 1 }
        qw(OpenTelemetry::Processor OpenTelemetry::Trace::Span::Processor OpenTelemetry::Logs::LogRecord::Processor) };

has 'exporter';
has batch_size     => 512;
has max_queue_size => 2048;
has timeout        => 10;
has queue          => sub { [] };

# The SDK only accepts processors that do its roles
sub DOES ( $self, $role ) { return ROLES->{$role} || $self->SUPER::DOES($role) }

sub on_start ( $self, @ ) { return }

sub on_end ( $self, $span ) {
    return unless $span->context->trace_flags->sampled;
    return $self->process( $span->snapshot );
}

sub on_emit ( $self, $log_record, @ ) { return $self->process($log_record) }

sub process ( $self, @items ) {
    my $queue = $self->queue;
    push @$queue, @items;

    # When the exports cannot keep up, the oldest are dropped first
    my $overflow = @$queue - $self->max_queue_size;
    splice @$queue, 0, $overflow if $overflow > 0;

    $self->export_queue if @$queue >= $self->batch_size;
    return;
}

# The exporter blocks (HTTP::Tiny, with retries): it runs in a child process, never in a web worker
sub export_queue ($self) {
    my @batch = splice @{ $self->queue };
    return unless @batch;
    return Mojo::IOLoop->subprocess(

        # uncoverable subroutine note:runs in the child process, which leaves with POSIX::_exit
        # uncoverable statement note:same
        sub { return $self->export_batch( \@batch ) },
        sub ( $, $error, @result ) { $self->_report( $error, @result ) },
    );
}

sub export_batch ( $self, $batch ) { return $self->exporter->export( $batch, $self->timeout ) }

sub force_flush ( $self, @ ) {
    my @batch = splice @{ $self->queue };
    return Future->done( @batch ? $self->export_batch( \@batch ) : EXPORT_RESULT_SUCCESS );
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
# The name is the interface of the OpenTelemetry processors
sub shutdown ( $self, @ ) { return $self->force_flush }
## use critic

sub _report ( $self, $error, @result ) {
    return if !$error && $result[0] == EXPORT_RESULT_SUCCESS;
    warn 'OpenTelemetry export failed: ' . ( $error ? $error : "result $result[0]" ) . "\n";
    return;
}

1;

=head1 NAME

Lembas::Telemetry::Processor - Export OpenTelemetry spans and log records from a forking web server

=head1 SYNOPSIS

  my $processor = Lembas::Telemetry::Processor->new( exporter => OpenTelemetry::Exporter::OTLP::Traces->new );
  OpenTelemetry->tracer_provider->add_span_processor($processor);
  Mojo::IOLoop->recurring( 5 => sub { $processor->export_queue } );

=head1 DESCRIPTION

A span and log record processor for the OpenTelemetry SDK. The SDK's batch processors export through IO::Async, which
needs a loop that never runs in a Mojolicious worker, and its simple processors block the request for every export.
This one queues what ends in the worker and exports each batch in a L<Mojo::IOLoop/"subprocess">, so the worker never
waits for the collector. C<force_flush> exports what is left in the worker itself, for the end of the process.

=head2 DOES

True for the OpenTelemetry processor roles.

=head2 on_start

Does nothing.

=head2 on_end

Queues a sampled span.

=head2 on_emit

Queues a log record.

=head2 process

Queues the given items, drops the oldest beyond C<max_queue_size>, exports once there are C<batch_size>.

=head2 export_queue

Exports what is queued, in a child process. Returns its L<Mojo::IOLoop::Subprocess>, if there was anything to export.

=head2 export_batch

Exports the given items with the exporter, in the current process.

=head2 force_flush

Exports what is queued, in the current process. Returns a done L<Future>.

=head2 shutdown

Same as C<force_flush>.

=cut
