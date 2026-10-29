package Lembas;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::mysql;
use Time::HiRes qw(gettimeofday tv_interval);
use Lembas::Config;
use Lembas::Error;
use Lembas::Model::ApiKeys;
use Lembas::Model::Clicks;
use Lembas::Model::Links;
use Lembas::Model::Users;
use Lembas::Telemetry;

our $VERSION = '1.0.0';

use constant CSP => join '; ', "default-src 'self'", "img-src 'self' data:", "style-src 'self'", "script-src 'self'",
    "frame-ancestors 'none'", "base-uri 'none'", "form-action 'self'";

# Request ids from upstream proxies are kept when they look like one
use constant REQUEST_ID => qr/\A[\w.-]{1,64}\z/a;

# The probes of Docker and the swarm, every few seconds: logged at the debug level
use constant PROBES => qr{\A/(?:health|ready)\z};

has mysql => sub ($self) {
    my $config = $self->config;
    my $mysql  = Mojo::mysql->strict_mode( $config->{db_url} );
    $mysql->password( $config->{db_password} ) if defined $config->{db_password};
    $mysql->migrations->name('lembas')->from_file( $self->home->child( 'migrations', 'lembas.sql' )->to_string );

    # Dates are stored and compared in UTC, whatever the time zone of the server
    $mysql->on( connection => sub ( $, $dbh ) { $dbh->do(q{SET time_zone = '+00:00'}) } );
    return $mysql;
};

has users => sub ($self) {
    return Lembas::Model::Users->new( mysql => $self->mysql, admin_emails => $self->config->{admin_emails} );
};

has api_keys => sub ($self) { Lembas::Model::ApiKeys->new( mysql => $self->mysql ) };

has clicks => sub ($self) { Lembas::Model::Clicks->new( mysql => $self->mysql ) };

has links => sub ($self) {
    my $config = $self->config;
    return Lembas::Model::Links->new(
        mysql         => $self->mysql,
        short_url     => $config->{short_url},
        ending_length => $config->{ending_length}
    );
};

has telemetry => sub ($self) { Lembas::Telemetry->new( %{ $self->config->{telemetry} }, version => $VERSION ) };

sub startup ($self) {

    # Test::Mojo->new( Lembas => { env => {...} } ) gives the environment of the tests
    my $config = Lembas::Config->from_env( $self->config->{config_override} ? $self->config->{env} : \%ENV );
    $self->config($config);
    $self->secrets( $config->{secrets} );
    $self->_sessions;
    $self->log->level( $config->{log_level} );
    $self->telemetry->register($self);

    push @{ $self->commands->namespaces }, 'Lembas::Command';
    $self->_helpers;
    $self->_hooks;
    $self->_routes;
    return;
}

# Lax, not Strict: the browser must send the cookie when the sign-in service redirects back to Lembas
sub _sessions ($self) {
    my $config   = $self->config;
    my $sessions = $self->sessions;
    $sessions->cookie_name('lembas');
    $sessions->samesite('Lax');
    $sessions->secure( scalar $config->{base_url} =~ /\Ahttps:/ );
    $sessions->default_expiration( $config->{session_days} * 86_400 );
    return;
}

sub _helpers ($self) {

    # The models, for the controllers
    for my $model (qw(api_keys clicks links users)) {
        $self->helper( $model => sub ($c) { $c->app->$model } );
    }

    # The signed-in user, while their account exists and is active
    $self->helper(
        current_user => sub ($c) {
            my $user_id = $c->session('user_id') or return;
            my $user    = $c->users->find($user_id);
            return $user if $user && $user->{is_active};
            delete $c->session->{user_id};
            return;
        }
    );

    # Renders a 403 for anybody else: "$c->require_admin or return"
    $self->helper(
        require_admin => sub ($c) {
            return 1 if $c->stash('user')->{is_admin};
            $c->render_error( Lembas::Error->new( code => 'forbidden', message => 'Admins only', status => 403 ) );
            return;
        }
    );

    # A Lembas::Error as the error document of the API; anything else is a bug, and a 500
    $self->helper(
        render_error => sub ( $c, $error ) {
            die $error unless Lembas::Error->caught($error);
            my $status = $error->status;
            return $c->render(
                openapi => { errors => [ { message => $error->message, path => '/' } ], status => $status },
                status  => $status
            );
        }
    );
    return;
}

sub _hooks ($self) {
    $self->hook(
        before_dispatch => sub ($c) {
            my $req = $c->req;
            my $id  = $req->headers->header('X-Request-ID');
            $req->request_id($id) if defined $id && $id =~ REQUEST_ID;
            $c->stash( 'lembas.started' => [gettimeofday] );
        }
    );

    $self->hook(
        after_dispatch => sub ($c) {
            my ( $req, $res ) = ( $c->req, $c->res );
            my $headers = $res->headers;
            $headers->header( 'X-Request-ID'              => $req->request_id );
            $headers->header( 'X-Content-Type-Options'    => 'nosniff' );
            $headers->header( 'X-Frame-Options'           => 'DENY' );
            $headers->header( 'Referrer-Policy'           => 'same-origin' );
            $headers->header( 'Content-Security-Policy'   => CSP );
            $headers->header( 'Strict-Transport-Security' => 'max-age=31536000' ) if $req->is_secure;

            # Static files are revalidated with their ETag, the rest is never stored
            $headers->cache_control( $c->stash('mojo.static') ? 'no-cache' : 'private, no-store' );

            my $path  = $req->url->path->to_string;
            my $level = $path =~ PROBES ? 'debug' : 'info';
            $c->app->log->$level(
                sprintf '%s %s %s %.1fms id=%s',
                $req->method, $path, $res->code, 1000 * tv_interval( $c->stash('lembas.started') ),
                $req->request_id
            );
        }
    );
    return;
}

sub _routes ($self) {
    my $r = $self->routes;
    $r->get('/health')->to('health#health')->name('health');
    $r->get('/ready')->to('health#ready')->name('ready');

    $self->plugin(
        OpenAPI => {
            url                    => $self->home->child( 'api', 'lembas.yaml' )->to_string,
            default_response_name  => 'DefaultResponse',
            default_response_codes => [ 400, 401, 403, 404, 409, 500, 501 ],
            security               => {
                apiKey => sub ( $c, $, $, $callback ) {
                    my $user_id = $c->api_keys->authenticate( $c->req->headers->header('X-Api-Key') // q{} )
                        or return $c->$callback('Invalid or missing API key');
                    $c->stash( user => $c->users->find($user_id), 'lembas.api_key' => 1 );
                    return $c->$callback;
                },
                session => sub ( $c, $, $, $callback ) {
                    my $user = $c->current_user or return $c->$callback('Not signed in');
                    $c->stash( user => $user );
                    return $c->$callback;
                },
            },
        }
    );
    return;
}

1;

=head1 NAME

Lembas - A URL shortener

=head1 SYNOPSIS

  script/lembas prefork --listen 'http://*:8080'

=head1 DESCRIPTION

The Mojolicious application. The configuration comes from the environment (see L<Lembas::Config> and the README).

=head2 mysql

The L<Mojo::mysql> connection to the database, with the migrations of F<migrations/lembas.sql>.

=head2 users

The L<Lembas::Model::Users> of the application, also the C<users> helper.

=head2 api_keys

The L<Lembas::Model::ApiKeys> of the application, also the C<api_keys> helper.

=head2 clicks

The L<Lembas::Model::Clicks> of the application, also the C<clicks> helper.

=head2 links

The L<Lembas::Model::Links> of the application, also the C<links> helper.

=head2 telemetry

The L<Lembas::Telemetry> of the application.

=head2 startup

Sets up the application.

=cut
