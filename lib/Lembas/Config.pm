package Lembas::Config;
use Mojo::Base -strict, -signatures;

use Mojo::File qw(path);
use Mojo::URL;

use constant DEFAULTS => {
    OIDC_ISSUER   => 'https://accounts.google.com',
    ENDING_LENGTH => 6,
    SESSION_DAYS  => 7,
    LOG_LEVEL     => 'info',
    SITE_NAME     => 'Lembas',
};

use constant REQUIRED   => [qw(BASE_URL DB_URL SECRETS OIDC_CLIENT_ID OIDC_CLIENT_SECRET ALLOWED_DOMAIN)];
use constant OPTIONAL   => [ qw(SHORT_URL DB_PASSWORD ADMIN_EMAILS), keys %{ DEFAULTS() } ];
use constant LOG_LEVELS => [qw(trace debug info warn error fatal)];
use constant MIN_SECRET => 16;
use constant TELEMETRY =>
    { schedule_delay => [ OTEL_BSP_SCHEDULE_DELAY => 5000 ], export_timeout => [ OTEL_BSP_EXPORT_TIMEOUT => 10_000 ] };

sub from_env ( $class, $env ) {
    my @errors;
    my %value = map { $_ => scalar _read( $env, "LEMBAS_$_", \@errors ) } @{ REQUIRED() }, @{ OPTIONAL() };
    push @errors, map { "LEMBAS_$_ is required" } grep { !defined $value{$_} } @{ REQUIRED() };
    for my $name ( keys %{ DEFAULTS() } ) {
        $value{$name} = DEFAULTS->{$name} unless defined $value{$name};
    }

    my %config = (
        base_url           => scalar _origin( $value{BASE_URL}, 'LEMBAS_BASE_URL', \@errors ),
        db_url             => $value{DB_URL},
        db_password        => $value{DB_PASSWORD},
        secrets            => [ grep { length } split /\s*,\s*/, $value{SECRETS} // q{} ],
        oidc_issuer        => scalar _origin( $value{OIDC_ISSUER}, 'LEMBAS_OIDC_ISSUER', \@errors ),
        oidc_client_id     => $value{OIDC_CLIENT_ID},
        oidc_client_secret => $value{OIDC_CLIENT_SECRET},
        allowed_domain     => lc( $value{ALLOWED_DOMAIN}                                                // q{} ),
        admin_emails       => { map { lc $_ => 1 } grep { length } split /[\s,]+/, $value{ADMIN_EMAILS} // q{} },
        ending_length      => $value{ENDING_LENGTH},
        session_days       => $value{SESSION_DAYS},
        log_level          => $value{LOG_LEVEL},
        site_name          => $value{SITE_NAME},
        telemetry          => _telemetry( $env, \@errors ),
    );
    my $short_url =
        defined $value{SHORT_URL}
        ? scalar _origin( $value{SHORT_URL}, 'LEMBAS_SHORT_URL', \@errors )
        : $config{base_url};
    $config{short_url} = "$short_url/" if defined $short_url;

    push @errors, 'LEMBAS_DB_URL must start with mariadb://'
        if defined $value{DB_URL} && $value{DB_URL} !~ m{\Amariadb://};
    push @errors, 'LEMBAS_SECRETS must list at least one secret' if defined $value{SECRETS} && !@{ $config{secrets} };
    push @errors, sprintf 'LEMBAS_SECRETS entries must be at least %d characters', MIN_SECRET
        if grep { length $_ < MIN_SECRET } @{ $config{secrets} };
    push @errors, 'LEMBAS_ALLOWED_DOMAIN must be a domain name, like example.org'
        if defined $value{ALLOWED_DOMAIN} && $config{allowed_domain} !~ /\A[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/;
    push @errors, 'LEMBAS_ENDING_LENGTH must be a number between 3 and 32'
        unless _between( $config{ending_length}, 3, 32 );
    push @errors, 'LEMBAS_SESSION_DAYS must be a number between 1 and 365'
        unless _between( $config{session_days}, 1, 365 );
    push @errors, 'LEMBAS_LOG_LEVEL must be one of ' . join( ', ', @{ LOG_LEVELS() } )
        unless grep { $_ eq $config{log_level} } @{ LOG_LEVELS() };

    die join( "\n  ", 'Invalid configuration:', @errors ) . "\n" if @errors;
    return \%config;
}

# The value of $name, or the content of the file named by ${name}_FILE (a Docker secret). Empty means unset.
sub _read ( $env, $name, $errors ) {
    my ( $value, $file ) = ( $env->{$name}, $env->{"${name}_FILE"} );
    return length $value ? $value : undef unless length $file;
    if ( length $value ) {
        push @$errors, "Set $name or ${name}_FILE, not both";
        return $value;
    }
    my $content = eval { path($file)->slurp };
    unless ( defined $content ) {
        push @$errors, "${name}_FILE: cannot read $file";
        return;
    }
    $content =~ s/\r?\n\z//;
    return length $content ? $content : undef;
}

# The scheme, host and port of an http(s) URL without a path, like https://example.org
sub _origin ( $value, $name, $errors ) {
    return unless defined $value;
    my $url = Mojo::URL->new($value);
    return $url->scheme . '://' . $url->host_port
        if ( $url->scheme // q{} ) =~ /\Ahttps?\z/
        && length( $url->host // q{} )
        && $url->path =~ m{\A/?\z}
        && !length $url->query->to_string;
    push @$errors, "$name must be an http or https URL without a path, like https://example.org";
    return;
}

sub _between ( $value, $min, $max ) { return $value =~ /\A[0-9]+\z/ && $value >= $min && $value <= $max }

# OpenTelemetry is configured by the standard OTEL_* variables, read by the SDK itself: these decide whether it runs
sub _telemetry ( $env, $errors ) {
    my $disabled = lc( $env->{OTEL_SDK_DISABLED} // 'false' );
    push @$errors, 'OTEL_SDK_DISABLED must be true or false' unless $disabled =~ /\A(?:true|false)\z/;

    my %telemetry = (
        enabled => ( $disabled ne 'true' && length( $env->{OTEL_EXPORTER_OTLP_ENDPOINT} ) ) ? 1 : 0,
        headers => scalar _read( $env, 'OTEL_EXPORTER_OTLP_HEADERS', $errors ),
    );
    for my $setting ( keys %{ TELEMETRY() } ) {
        my ( $name, $default ) = @{ TELEMETRY->{$setting} };
        my $milliseconds = defined $env->{$name} ? $env->{$name} : $default;
        if ( $milliseconds =~ /\A[1-9][0-9]*\z/ ) {
            $telemetry{$setting} = $milliseconds / 1000;
        } else {
            push @$errors, "$name must be a number of milliseconds";
        }
    }
    return \%telemetry;
}

1;

=head1 NAME

Lembas::Config - The configuration of Lembas, from the environment

=head1 SYNOPSIS

  my $config = Lembas::Config->from_env( \%ENV );

=head1 DESCRIPTION

Reads the C<LEMBAS_*> variables, and the C<OTEL_*> variables that decide whether OpenTelemetry runs. Every
C<LEMBAS_*> variable, and C<OTEL_EXPORTER_OTLP_HEADERS>, can instead be read from the file named by the same variable
with a C<_FILE> suffix (a Docker secret). Empty values count as unset.

=head2 from_env

Returns the configuration as a hash reference, or dies listing every problem found.

=cut
