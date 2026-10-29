package Lembas;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::mysql;
use Lembas::Config;

our $VERSION = '1.0.0';

has mysql => sub ($self) {
    my $config = $self->config;
    my $mysql  = Mojo::mysql->strict_mode( $config->{db_url} );
    $mysql->password( $config->{db_password} ) if defined $config->{db_password};
    $mysql->migrations->name('lembas')->from_file( $self->home->child( 'migrations', 'lembas.sql' )->to_string );

    # Dates are stored and compared in UTC, whatever the time zone of the server
    $mysql->on( connection => sub ( $, $dbh ) { $dbh->do(q{SET time_zone = '+00:00'}) } );
    return $mysql;
};

sub startup ($self) {

    # Test::Mojo->new( Lembas => { env => {...} } ) gives the environment of the tests
    my $config = Lembas::Config->from_env( $self->config->{config_override} ? $self->config->{env} : \%ENV );
    $self->config($config);
    $self->secrets( $config->{secrets} );
    $self->log->level( $config->{log_level} );

    push @{ $self->commands->namespaces }, 'Lembas::Command';
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

=head2 startup

Sets up the application.

=cut
