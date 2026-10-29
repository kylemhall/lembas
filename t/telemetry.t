use Mojo::Base -strict, -signatures;

use Test::More;
use Lembas::Test qw(test_app);
use Test::NoWarnings;
use OpenTelemetry;
use OpenTelemetry::Constants qw(SPAN_KIND_CLIENT SPAN_KIND_SERVER);
use OpenTelemetry::Instrumentation::Mojo::UserAgent;
use Mojo::File;
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojolicious;
use Lembas::Telemetry;
use Lembas::Test::Telemetry qw(log_records spans start_in_memory);

plan tests => 15;

sub server_span () {
    my @spans = grep { $_->kind == SPAN_KIND_SERVER } @{ spans() };
    return $spans[0];
}

subtest 'off without an endpoint' => sub {
    plan tests => 3;
    my $t       = test_app();
    my $started = 0;
    $t->app->telemetry->sdk_starter( sub (@) { $started++ } );
    $t->get_ok('/nowhere')->status_is(404);
    is( $started, 0, 'the SDK never starts' );
};

# Nothing has started yet: nothing to export at exit
Lembas::Telemetry::at_exit();

my $t = test_app( OTEL_EXPORTER_OTLP_ENDPOINT => 'http://collector.invalid:4318' );
$t->app->telemetry->sdk_starter( \&start_in_memory );

# The requests of Test::Mojo would be traced too, with their own trace context: only where they are wanted
OpenTelemetry::Instrumentation::Mojo::UserAgent->uninstall;
$t->app->log->handle( Mojo::File->new('/dev/null')->open('>') );

my $routes = $t->app->routes;
$routes->get( '/'                    => sub ($c) { $c->render( text => 'home' ) } );
$routes->get( '/_test/links/:ending' => sub ($c) { $c->render( text => 'a link' ) } );
$routes->get( '/_test/error'         => sub ($c) { $c->render( text => 'broken', status => 500 ) } );
$routes->get( '/_test/die'           => sub ($c) { die "Broken\nat the second line\n" } );
$routes->get( '/_test/die_object'    => sub ($c) { die Lembas::Error->new( code => 'broken', message => 'Broken' ) } );
$routes->get(
    '/_test/db' => sub ($c) {
        $c->app->mysql->db->query( 'SELECT ? AS answer', 42 );
        $c->render( text => 'queried' );
    }
);

# Another service, like the sign-in service of Google for Lembas::Model::OIDC
my $remote_app = Mojolicious->new;
$remote_app->routes->get( '/remote' => sub ($c) { $c->render( text => 'remote' ) } );
my $remote = Mojo::UserAgent->new;
$remote->server->app($remote_app);
$routes->get( '/_test/fetch' => sub ($c) { $c->render( text => $remote->get('/remote')->result->body ) } );
$routes->get(
    '/_test/log' => sub ($c) {
        $c->app->log->$_("logged at $_") for qw(trace debug info warn error fatal);
        $c->render( text => $c->app->log->format->( time, 'info', 'formatted' ) );
    }
);

subtest 'server spans' => sub {
    plan tests => 11;
    $t->get_ok( '/_test/links/abc?key=secret-api-key' => { 'X-Forwarded-For' => '203.0.113.9' } )->status_is(200);
    is( $t->app->telemetry->started_pid, $$, 'the SDK started with the first request' );
    my $span       = server_span();
    my $attributes = $span->attributes;
    is( $span->name, 'GET /_test/links/:ending', 'named after the route' );
    is_deeply(
        [ @$attributes{qw(http.request.method http.route url.path http.response.status_code)} ],
        [ 'GET', '/_test/links/:ending', '/_test/links/abc', 200 ],
        'method, route, path and status'
    );
    is( $attributes->{'url.scheme'},          'http',               'scheme' );
    is( $attributes->{'user_agent.original'}, 'Mojolicious (Perl)', 'user agent' );
    ok( !exists $attributes->{'url.query'},      'no query: the API keys of the Polr API travel in it' );
    ok( !exists $attributes->{'client.address'}, 'no client address' );
    unlike( join( q{ }, values %$attributes ), qr/secret-api-key|203\.0\.113\.9/, 'neither appears anywhere' );
    ok( $span->status->is_unset, 'not an error' );
};

subtest 'the root' => sub {
    plan tests => 2;
    $t->get_ok('/');
    is( server_span()->name, 'GET /', 'its route is /' );
};

subtest 'no user agent' => sub {
    plan tests => 2;
    my $transactor = $t->ua->transactor;
    my $name       = $transactor->name;
    $transactor->name(q{});
    $t->get_ok('/_test/links/abc');
    $transactor->name($name);
    ok( !exists server_span()->attributes->{'user_agent.original'}, 'no attribute' );
};

subtest 'server errors' => sub {
    plan tests => 3;
    $t->get_ok('/_test/error')->status_is(500);
    ok( server_span()->status->is_error, 'an error' );
};

subtest 'exceptions' => sub {
    plan tests => 5;
    $t->get_ok('/_test/die')->status_is(500);
    my $span = server_span();
    ok( $span->status->is_error, 'an error' );
    is( $span->status->description, 'Broken',    'the first line of the message' );
    is( ( $span->events )[0]->name, 'exception', 'the exception is recorded' );
};

subtest 'untraced' => sub {
    plan tests => 4;
    $t->get_ok('/health');
    $t->get_ok('/robots.txt');
    $t->get_ok('/vendor/nothing.js');
    is_deeply(
        [ grep { $_->kind == SPAN_KIND_SERVER } @{ spans() } ], [],
        'no span for the probes and the static files'
    );
};

subtest 'incoming trace context' => sub {
    plan tests => 3;
    my ( $trace_id, $parent_id ) = ( '0af7651916cd43dd8448eb211c80319c', 'b7ad6b7169203331' );
    $t->get_ok( '/_test/links/abc' => { traceparent => "00-$trace_id-$parent_id-01" } );
    my $span = server_span();
    is( $span->hex_trace_id,       $trace_id,  'the trace of the caller' );
    is( $span->hex_parent_span_id, $parent_id, 'the span of the caller is the parent' );
};

subtest 'database spans' => sub {
    plan tests => 3;
    $t->get_ok('/_test/db');
    my @spans    = @{ spans() };
    my ($query)  = grep { ( $_->attributes->{'db.statement'} // q{} ) eq 'SELECT ? AS answer' } @spans;
    my ($server) = grep { $_->kind == SPAN_KIND_SERVER } @spans;
    ok( $query, 'the query, with its placeholder and not its value' );
    is( $query->hex_parent_span_id, $server->hex_span_id, 'a child of the request' );
};

subtest 'outgoing requests' => sub {
    plan tests => 4;
    OpenTelemetry::Instrumentation::Mojo::UserAgent->install;
    $t->get_ok('/_test/fetch')->content_is('remote');
    OpenTelemetry::Instrumentation::Mojo::UserAgent->uninstall;
    my @spans    = @{ spans() };
    my ($client) = grep { $_->kind == SPAN_KIND_CLIENT && $_->attributes->{'url.full'} =~ m{/remote\z} } @spans;
    my ($server) = grep { $_->kind == SPAN_KIND_SERVER } @spans;
    is( $client->attributes->{'http.response.status_code'}, 200,                  'the request is traced' );
    is( $client->hex_parent_span_id,                        $server->hex_span_id, 'a child of the request' );
};

subtest 'log records' => sub {
    plan tests => 5;
    $t->app->log->level('trace');
    $t->get_ok('/_test/log');
    my $trace_id = server_span()->hex_trace_id;
    my @records  = grep { $_->body =~ /\Alogged at/ } @{ log_records() };
    is_deeply(
        { map { $_->body => $_->severity_number } @records },
        {
            'logged at trace' => 1,
            'logged at debug' => 5,
            'logged at info'  => 9,
            'logged at warn'  => 13,
            'logged at error' => 17,
            'logged at fatal' => 21,
        },
        'every level, with its severity'
    );
    is_deeply( [ map { $_->hex_trace_id } @records ], [ ($trace_id) x 6 ], 'each belongs to the trace of its request' );
    like( $t->tx->res->body, qr/formatted trace_id=[0-9a-f]{32} span_id=[0-9a-f]{16}\n\z/, 'log lines show the trace' );
    unlike( $t->app->log->format->( time, 'info', 'outside' ), qr/trace_id/, 'not outside a request' );
    $t->app->log->level('fatal');
};

subtest 'once per process' => sub {
    plan tests => 3;
    my $telemetry = $t->app->telemetry;
    my $starts    = 0;
    $telemetry->sdk_starter( sub ($telemetry) { $starts++; start_in_memory($telemetry) } );
    $t->get_ok('/_test/links/abc');
    $telemetry->started_pid(1);
    $t->get_ok('/_test/links/abc');
    is( $starts, 1, 'started again in a new process only' );
};

subtest 'at_exit() tests' => sub {
    plan tests => 2;
    my $telemetry = $t->app->telemetry;
    my $pid       = $telemetry->started_pid;
    $telemetry->started_pid(1);
    is_deeply( [ Lembas::Telemetry::at_exit() ], [], 'nothing in a process that did not start the SDK' );
    $telemetry->started_pid($pid);
    is_deeply( [ Lembas::Telemetry::at_exit() ], [], 'flushed in the one that did' );
};

subtest 'start_sdk() tests' => sub {
    plan tests => 6;
    local %ENV = ( %ENV, OTEL_EXPORTER_OTLP_ENDPOINT => 'http://127.0.0.1:1' );
    delete local $ENV{OTEL_SERVICE_NAME};
    delete local $ENV{OTEL_RESOURCE_ATTRIBUTES};
    my $telemetry = Lembas::Telemetry->new(
        version        => '1.2.3',
        headers        => 'Authorization=ApiKey abc',
        schedule_delay => 0.05,
        export_timeout => 1
    );

    $telemetry->start_sdk;

    # Exports every schedule_delay seconds: nothing is queued yet, so nothing goes anywhere
    Mojo::IOLoop->timer( 0.2 => sub { Mojo::IOLoop->stop } );
    Mojo::IOLoop->start;

    isa_ok( OpenTelemetry->tracer_provider, 'OpenTelemetry::SDK::Trace::TracerProvider', 'the tracer provider' );
    my $span = OpenTelemetry->tracer_provider->tracer( name => 'test' )->create_span( name => 'test' );
    is_deeply(
        [ @{ $span->snapshot->resource->attributes }{qw(service.name service.version)} ],
        [ 'lembas', '1.2.3' ],
        'the resource: the name and the version of the service'
    );
    ok( !exists $ENV{OTEL_EXPORTER_OTLP_HEADERS}, 'the environment is left as it was' );

    local $ENV{OTEL_SERVICE_NAME}        = 'links';
    local $ENV{OTEL_RESOURCE_ATTRIBUTES} = 'deployment.environment.name=test';
    $telemetry->headers(undef)->start_sdk;
    my $attributes =
        OpenTelemetry->tracer_provider->tracer( name => 'test' )
        ->create_span( name => 'test' )
        ->snapshot->resource->attributes;
    is( $attributes->{'service.name'},                'links', 'the name from OTEL_SERVICE_NAME' );
    is( $attributes->{'deployment.environment.name'}, 'test',  'the attributes of OTEL_RESOURCE_ATTRIBUTES' );
    is( $attributes->{'service.version'},             '1.2.3', 'and the version' );

    start_in_memory();
};
