requires 'perl', '5.040';

requires 'Mojolicious',                  '>= 9.40';
requires 'Mojolicious::Plugin::OpenAPI', '>= 5.12';
requires 'JSON::Validator',              '>= 5.17';
requires 'YAML::XS';    # JSON::Validator reads api/lembas.yaml with it
requires 'Mojo::mysql',     '>= 1.28';
requires 'DBD::MariaDB',    '>= 1.21';
requires 'Crypt::JWT',      '>= 0.035';
requires 'CryptX',          '>= 0.080';
requires 'IO::Socket::SSL', '>= 2.009';    # HTTPS to Google

requires 'OpenTelemetry',                 '>= 0.039';
requires 'OpenTelemetry::SDK',            '>= 0.100';
requires 'OpenTelemetry::Exporter::OTLP', '>= 0.022';

# First release: reviewed before any upgrade
requires 'OpenTelemetry::Instrumentation::Mojo::UserAgent', '== 0.01';
requires 'Syntax::Keyword::Dynamically';

# The test suite and the quality checks: cpanm --with-feature=test (the test image)
feature 'test', 'Test suite, coverage and code quality' => sub {
    requires 'Test::More',         '>= 0.98';
    requires 'Test::NoWarnings',   '>= 1.06';
    requires 'Test::MockModule',   '>= 0.180';
    requires 'Test::Pod',          '>= 1.52';
    requires 'Perl::Critic',       '== 1.156';
    requires 'Test::Perl::Critic', '== 1.04';
    requires 'Perl::Tidy',         '== 20250912';
    requires 'Devel::Cover',       '== 1.52';
};
