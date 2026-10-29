use Mojo::Base -strict, -signatures;

use Test::More tests => 13;
use Test::NoWarnings;
use Mojo::File qw(tempdir);
use Lembas::Config;

my %required = (
    LEMBAS_BASE_URL           => 'https://lembas.example.org',
    LEMBAS_DB_URL             => 'mariadb://lembas@db/lembas',
    LEMBAS_SECRETS            => 'a-secret-of-20-chars',
    LEMBAS_OIDC_CLIENT_ID     => 'client-id',
    LEMBAS_OIDC_CLIENT_SECRET => 'client-secret',
    LEMBAS_ALLOWED_DOMAIN     => 'Example.org',
);

sub config_for (%env) { return Lembas::Config->from_env( { %required, %env } ) }

# The error message, or the empty string when the configuration is valid
sub errors_for (%env) {
    return eval { config_for(%env); 1 } ? q{} : $@;
}

subtest 'defaults' => sub {
    plan tests => 1;
    is_deeply(
        config_for(),
        {
            base_url           => 'https://lembas.example.org',
            short_url          => 'https://lembas.example.org/',
            db_url             => 'mariadb://lembas@db/lembas',
            db_password        => undef,
            secrets            => ['a-secret-of-20-chars'],
            oidc_issuer        => 'https://accounts.google.com',
            oidc_client_id     => 'client-id',
            oidc_client_secret => 'client-secret',
            allowed_domain     => 'example.org',
            admin_emails       => {},
            ending_length      => 6,
            session_days       => 7,
            log_level          => 'info',
            site_name          => 'Lembas',
            telemetry          => { enabled => 0, headers => undef, schedule_delay => 5, export_timeout => 10 },
        },
        'only the required settings'
    );
};

subtest 'every setting' => sub {
    plan tests => 10;
    my $config = config_for(
        LEMBAS_SHORT_URL            => 'https://short.example/',
        LEMBAS_DB_PASSWORD          => 'db-password',
        LEMBAS_SECRETS              => 'first-secret-of-20ch , second-secret-of-20c',
        LEMBAS_OIDC_ISSUER          => 'http://oidc.test:3000',
        LEMBAS_ADMIN_EMAILS         => 'A@Example.org, b@example.org c@example.org',
        LEMBAS_ENDING_LENGTH        => 8,
        LEMBAS_SESSION_DAYS         => 30,
        LEMBAS_LOG_LEVEL            => 'debug',
        LEMBAS_SITE_NAME            => 'Links',
        OTEL_EXPORTER_OTLP_ENDPOINT => 'http://collector:4318',
        OTEL_EXPORTER_OTLP_HEADERS  => 'Authorization=ApiKey abc',
        OTEL_BSP_SCHEDULE_DELAY     => 1000,
        OTEL_BSP_EXPORT_TIMEOUT     => 2500,
    );
    is( $config->{short_url},   'https://short.example/', 'short URL, normalized' );
    is( $config->{db_password}, 'db-password',            'database password' );
    is_deeply( $config->{secrets}, [ 'first-secret-of-20ch', 'second-secret-of-20c' ], 'secrets, in order' );
    is( $config->{oidc_issuer}, 'http://oidc.test:3000', 'OpenID Connect issuer' );
    is_deeply(
        $config->{admin_emails},
        { 'a@example.org' => 1, 'b@example.org' => 1, 'c@example.org' => 1 },
        'admin emails, lower cased'
    );
    is( $config->{ending_length}, 8,       'ending length' );
    is( $config->{session_days},  30,      'session days' );
    is( $config->{log_level},     'debug', 'log level' );
    is( $config->{site_name},     'Links', 'site name' );
    is_deeply(
        $config->{telemetry},
        { enabled => 1, headers => 'Authorization=ApiKey abc', schedule_delay => 1, export_timeout => 2.5 },
        'telemetry'
    );
};

subtest 'required settings' => sub {
    my @names = sort keys %required;
    plan tests => 2 * @names;
    for my $name (@names) {
        like( errors_for( $name => undef ), qr/\Q$name\E is required/, "$name is required" );
        like( errors_for( $name => q{} ),   qr/\Q$name\E is required/, "an empty $name is unset" );
    }
};

subtest 'files' => sub {
    plan tests => 6;
    my $dir = tempdir;
    $dir->child('secret')->spew("from-a-file-of-20-chars\n");
    $dir->child('crlf')->spew("from-a-crlf-file-20chars\r\n");
    $dir->child('empty')->spew(q{});

    is_deeply(
        config_for( LEMBAS_SECRETS => undef, LEMBAS_SECRETS_FILE => "$dir/secret" )->{secrets},
        ['from-a-file-of-20-chars'], 'the value is read from the file, without its end of line'
    );
    is_deeply(
        config_for( LEMBAS_SECRETS => undef, LEMBAS_SECRETS_FILE => "$dir/crlf" )->{secrets},
        ['from-a-crlf-file-20chars'], 'a Windows end of line too'
    );
    like(
        errors_for( LEMBAS_SECRETS_FILE => "$dir/secret" ), qr/Set LEMBAS_SECRETS or LEMBAS_SECRETS_FILE, not both/,
        'not both'
    );
    like(
        errors_for( LEMBAS_SECRETS => undef, LEMBAS_SECRETS_FILE => "$dir/missing" ),
        qr{LEMBAS_SECRETS_FILE: cannot read \Q$dir\E/missing},
        'a file that cannot be read'
    );
    like(
        errors_for( LEMBAS_SECRETS => undef, LEMBAS_SECRETS_FILE => "$dir/empty" ), qr/LEMBAS_SECRETS is required/,
        'an empty file is unset'
    );
    is(
        config_for( LEMBAS_DB_PASSWORD_FILE => "$dir/secret" )->{db_password},
        'from-a-file-of-20-chars', 'any setting can be read from a file'
    );
};

subtest 'URLs' => sub {
    my %invalid = (
        'no scheme'    => 'lembas.example.org',
        'not http'     => 'ftp://lembas.example.org',
        'no host'      => 'https:lembas',
        'with a path'  => 'https://lembas.example.org/lembas',
        'empty host'   => 'https://',
        'with a query' => 'https://lembas.example.org/?a=1',
    );
    plan tests => 3 + keys %invalid;
    like(
        errors_for( LEMBAS_BASE_URL => $invalid{$_} ),
        qr/LEMBAS_BASE_URL must be an http or https URL without a path/, "invalid base URL: $_"
    ) for sort keys %invalid;
    is(
        config_for( LEMBAS_BASE_URL => 'http://localhost:3000/' )->{base_url},
        'http://localhost:3000', 'a trailing slash is dropped, the port kept'
    );
    like( errors_for( LEMBAS_SHORT_URL => 'bywater.solutions' ), qr/LEMBAS_SHORT_URL must be/, 'invalid short URL' );
    like(
        errors_for( LEMBAS_OIDC_ISSUER => 'accounts.google.com' ), qr/LEMBAS_OIDC_ISSUER must be/,
        'invalid OpenID Connect issuer'
    );
};

subtest 'database' => sub {
    plan tests => 1;
    like(
        errors_for( LEMBAS_DB_URL => 'mysql://lembas@db/lembas' ), qr/LEMBAS_DB_URL must start with mariadb:\/\//,
        'mysql:// would need DBD::mysql, which is not installed'
    );
};

subtest 'secrets' => sub {
    plan tests => 2;
    like(
        errors_for( LEMBAS_SECRETS => 'long-enough-secret-20, short' ),
        qr/LEMBAS_SECRETS entries must be at least 16 characters/, 'every secret must be long enough'
    );
    like( errors_for( LEMBAS_SECRETS => ' , ' ), qr/LEMBAS_SECRETS must list at least one secret/, 'only separators' );
};

subtest 'allowed domain' => sub {
    plan tests => 2;
    like(
        errors_for( LEMBAS_ALLOWED_DOMAIN => 'localhost' ), qr/LEMBAS_ALLOWED_DOMAIN must be a domain name/,
        'a domain has a dot'
    );
    like(
        errors_for( LEMBAS_ALLOWED_DOMAIN => 'example.org!' ), qr/LEMBAS_ALLOWED_DOMAIN must be a domain name/,
        'only letters, digits, dots and dashes'
    );
};

subtest 'numbers' => sub {
    plan tests => 8;
    like(
        errors_for( LEMBAS_ENDING_LENGTH => 'six' ), qr/LEMBAS_ENDING_LENGTH must be a number between 3 and 32/,
        'not a number'
    );
    like( errors_for( LEMBAS_ENDING_LENGTH => 2 ),  qr/LEMBAS_ENDING_LENGTH must be/, 'too short' );
    like( errors_for( LEMBAS_ENDING_LENGTH => 33 ), qr/LEMBAS_ENDING_LENGTH must be/, 'too long' );
    is( config_for( LEMBAS_ENDING_LENGTH => 3 )->{ending_length},  3,  'shortest' );
    is( config_for( LEMBAS_ENDING_LENGTH => 32 )->{ending_length}, 32, 'longest' );
    like(
        errors_for( LEMBAS_SESSION_DAYS => 0 ), qr/LEMBAS_SESSION_DAYS must be a number between 1 and 365/,
        'zero days'
    );
    like( errors_for( LEMBAS_SESSION_DAYS => 366 ), qr/LEMBAS_SESSION_DAYS must be/, 'more than a year' );
    is( config_for( LEMBAS_SESSION_DAYS => 365 )->{session_days}, 365, 'a year' );
};

subtest 'log level' => sub {
    plan tests => 1;
    my $message = 'LEMBAS_LOG_LEVEL must be one of trace, debug, info, warn, error, fatal';
    like( errors_for( LEMBAS_LOG_LEVEL => 'verbose' ), qr/\Q$message\E/, 'unknown level' );
};

subtest 'telemetry' => sub {
    plan tests => 8;
    my $endpoint = 'http://collector:4318';
    is( config_for( OTEL_EXPORTER_OTLP_ENDPOINT => $endpoint )->{telemetry}{enabled}, 1, 'on with an endpoint' );
    is( config_for()->{telemetry}{enabled},                                           0, 'off without an endpoint' );
    is(
        config_for( OTEL_EXPORTER_OTLP_ENDPOINT => $endpoint, OTEL_SDK_DISABLED => 'TRUE' )->{telemetry}{enabled},
        0, 'off when disabled'
    );
    is(
        config_for( OTEL_EXPORTER_OTLP_ENDPOINT => $endpoint, OTEL_SDK_DISABLED => 'false' )->{telemetry}{enabled},
        1, 'on when not disabled'
    );
    like( errors_for( OTEL_SDK_DISABLED => 'yes' ), qr/OTEL_SDK_DISABLED must be true or false/, 'a boolean' );
    like(
        errors_for( OTEL_BSP_SCHEDULE_DELAY => 'soon' ), qr/OTEL_BSP_SCHEDULE_DELAY must be a number of milliseconds/,
        'delay in milliseconds'
    );
    like(
        errors_for( OTEL_BSP_EXPORT_TIMEOUT => 0 ), qr/OTEL_BSP_EXPORT_TIMEOUT must be a number of milliseconds/,
        'no zero timeout'
    );

    my $dir = tempdir;
    $dir->child('headers')->spew("Authorization=ApiKey from-file\n");
    is(
        config_for( OTEL_EXPORTER_OTLP_HEADERS_FILE => "$dir/headers" )->{telemetry}{headers},
        'Authorization=ApiKey from-file', 'headers from a file (a Docker secret)'
    );
};

subtest 'every problem at once' => sub {
    plan tests => 3;
    my $errors = eval { Lembas::Config->from_env( { LEMBAS_LOG_LEVEL => 'loud' } ); 1 } ? q{} : $@;
    like( $errors, qr/\AInvalid configuration:\n/,   'one message' );
    like( $errors, qr/LEMBAS_BASE_URL is required/,  'with the missing settings' );
    like( $errors, qr/LEMBAS_LOG_LEVEL must be one/, 'and the invalid ones' );
};
