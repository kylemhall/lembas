package Lembas;
use Mojo::Base 'Mojolicious', -signatures;

use Lembas::Config;

our $VERSION = '1.0.0';

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

=head2 startup

Sets up the application.

=cut
