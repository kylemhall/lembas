package Lembas::Telemetry;
use Mojo::Base -base, -signatures;

use Mojo::IOLoop;
use OpenTelemetry;
use OpenTelemetry::Constants qw(SPAN_KIND_SERVER SPAN_STATUS_ERROR);
use OpenTelemetry::Context;
use OpenTelemetry::Exporter::OTLP::Logs;
use OpenTelemetry::Exporter::OTLP::Traces;
use OpenTelemetry::Instrumentation::DBI;
use OpenTelemetry::Instrumentation::Mojo::UserAgent;
use OpenTelemetry::Trace;
use Syntax::Keyword::Dynamically;
use Time::HiRes qw(time);
use Lembas::Telemetry::Processor;

# The severity numbers of the OpenTelemetry log data model
use constant SEVERITY => { trace => 1, debug => 5, info => 9, warn => 13, error => 17, fatal => 21 };

# Probes and static files: many requests, nothing to learn from them
my $probes   = qr{\A/(?:health|ready)\z};
my $static   = qr{\A/(?:favicon\.ico|robots\.txt)\z|\A/(?:css|js|vendor)/};
my $untraced = qr/$probes|$static/;

has [qw(enabled headers schedule_delay export_timeout version)];
has started_pid => 0;
has sdk_starter => sub { \&start_sdk };

# The instance that started the SDK in this process: what it queued is exported at exit
my $started;

sub register ( $self, $app ) {
    return $self unless $self->enabled;

    # These wrap methods only: until the SDK starts in a worker, they talk to the no-op providers of the API
    OpenTelemetry::Instrumentation::DBI->install;
    OpenTelemetry::Instrumentation::Mojo::UserAgent->install;

    $app->hook( around_dispatch => sub ( $next, $c ) { return $self->_trace( $next, $c ) } );
    $app->hook( after_dispatch  => sub ($c) { $self->_end($c) } );
    $app->hook(
        around_action => sub ( $next, $c, @ ) {
            my $route = $c->match->endpoint->to_string;
            $route = '/' unless length $route;
            my $span = OpenTelemetry::Trace->span_from_context;
            $span->set_name( $c->req->method . " $route" );
            $span->set_attribute( 'http.route' => $route );
            return $next->();
        }
    );

    my $log    = $app->log;
    my $format = $log->format;
    $log->on( message => sub ( $, $level, @lines ) { $self->_emit_log( $level, @lines ) } );
    $log->format(
        sub ( $time, $level, @lines ) {
            my $span_context = OpenTelemetry::Trace->span_from_context->context;
            return $format->( $time, $level, @lines ) unless $span_context->valid;
            return $format->(
                $time, $level,
                join( "\n", @lines )
                    . sprintf( ' trace_id=%s span_id=%s', $span_context->hex_trace_id, $span_context->hex_span_id )
            );
        }
    );
    return $self;
}

# The SDK starts in each process on its first request: after the fork of the prefork server
sub ensure_started ($self) {
    return if $self->started_pid == $$;
    $self->sdk_starter->($self);
    $self->started_pid($$);
    $started = $self;
    return;
}

sub start_sdk ($self) {
    my %env = ( %ENV, OTEL_TRACES_EXPORTER => 'none', OTEL_LOGS_EXPORTER => 'none' );
    $env{OTEL_SERVICE_NAME}        = 'lembas' unless defined $env{OTEL_SERVICE_NAME};
    $env{OTEL_RESOURCE_ATTRIBUTES} = join ',', 'service.version=' . $self->version,
        grep { defined } $env{OTEL_RESOURCE_ATTRIBUTES};
    $env{OTEL_EXPORTER_OTLP_HEADERS} = $self->headers if defined $self->headers;
    local %ENV = %env;

    # The SDK builds the providers, the resource, the sampler and the propagators from the environment, without its
    # batch processors: they need an IO::Async loop, which never runs here (Lembas::Telemetry::Processor)
    require OpenTelemetry::SDK;
    OpenTelemetry::SDK->import;

    my %processor = (
        spans => Lembas::Telemetry::Processor->new(
            exporter => OpenTelemetry::Exporter::OTLP::Traces->new,
            timeout  => $self->export_timeout
        ),
        logs => Lembas::Telemetry::Processor->new(
            exporter => OpenTelemetry::Exporter::OTLP::Logs->new,
            timeout  => $self->export_timeout
        ),
    );
    OpenTelemetry->tracer_provider->add_span_processor( $processor{spans} );
    OpenTelemetry->logger_provider->add_log_record_processor( $processor{logs} );
    Mojo::IOLoop->recurring( $self->schedule_delay => sub { $_->export_queue for values %processor } );
    return;
}

sub at_exit {
    return unless $started && $started->started_pid == $$;
    $_->force_flush->get for OpenTelemetry->tracer_provider, OpenTelemetry->logger_provider;
    return;
}

END { at_exit() }

sub _trace ( $self, $next, $c ) {
    my $req  = $c->req;
    my $path = $req->url->path->to_string;
    return $next->() if $path =~ $untraced;
    $self->ensure_started;

    # No query (Polr API keys and sign-in codes travel in it), no client address, no email: none is recorded
    my $headers = $req->headers;
    my $agent   = $headers->user_agent;
    my $url     = $req->url->to_abs;
    my $context =
        OpenTelemetry->propagator->extract( $headers, undef, sub ( $carrier, $key ) { $carrier->header($key) } );
    my $span = OpenTelemetry->tracer_provider->tracer( name => 'lembas', version => $self->version )->create_span(
        name       => $req->method,
        kind       => SPAN_KIND_SERVER,
        parent     => $context,
        attributes => {
            'http.request.method'      => $req->method,
            'url.path'                 => $path,
            'url.scheme'               => $url->scheme,
            'server.address'           => $url->host,
            'network.protocol.version' => $req->version,
            length $agent ? ( 'user_agent.original' => $agent ) : (),
        },
    );
    $c->stash( 'lembas.span' => $span );
    dynamically OpenTelemetry::Context->current = OpenTelemetry::Trace->context_with_span( $span, $context );

    return 1 if eval { $next->(); 1 };
    my $error = $@;
    $span->record_exception($error);
    $c->stash( 'lembas.error' => ( split /\n/, "$error" )[0] );
    die $error;
}

# After the response is rendered, also when the exception page is
sub _end ( $self, $c ) {
    my $span   = delete $c->stash->{'lembas.span'} or return;
    my $status = $c->res->code;
    $span->set_attribute( 'http.response.status_code' => $status );
    if ( my $user = $c->stash('user') ) {
        $span->set_attribute( 'user.id' => $user->{id} );
    }
    $span->set_status( SPAN_STATUS_ERROR, $c->stash('lembas.error') ) if $status >= 500;
    $span->end;
    return;
}

sub _emit_log ( $self, $level, @lines ) {
    OpenTelemetry->logger_provider->logger( name => 'lembas', version => $self->version )->emit_record(
        timestamp       => time,
        context         => OpenTelemetry::Context->current,
        severity_text   => uc $level,
        severity_number => SEVERITY->{$level},
        body            => join( "\n", @lines ),
    );
    return;
}

1;

=head1 NAME

Lembas::Telemetry - OpenTelemetry traces and logs

=head1 SYNOPSIS

  Lembas::Telemetry->new( enabled => 1, schedule_delay => 5, export_timeout => 10, version => '1.0.0' )
      ->register($app);

=head1 DESCRIPTION

When enabled (see L<Lembas::Config>), every request but the probes and the static files gets a server span, the
database queries and the requests to the sign-in service get child spans, and the log lines are sent as OpenTelemetry
log records with the trace they belong to. The standard C<OTEL_*> variables configure the SDK and its exporters.

The SDK starts in each process on its first request, after the prefork server forked it, and what is left to export
is exported when the process exits.

=head2 register

Installs the hooks, the log bridge and the instrumentations on the application, when enabled.

=head2 ensure_started

Starts the SDK with C<sdk_starter>, once per process.

=head2 start_sdk

The default C<sdk_starter>: the SDK configured from the environment, with OTLP exporters behind
L<Lembas::Telemetry::Processor>.

=head2 at_exit

Exports what is still queued, in the process that started the SDK.

=cut
