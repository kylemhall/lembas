package Lembas;
use Mojo::Base 'Mojolicious', -signatures;

our $VERSION = '1.0.0';

sub startup ($self) {
    push @{ $self->commands->namespaces }, 'Lembas::Command';
    return;
}

1;

=head1 NAME

Lembas - A URL shortener

=head1 SYNOPSIS

  script/lembas prefork --listen 'http://*:8080'

=head1 DESCRIPTION

The Mojolicious application. See the README for the configuration and the deployment.

=head2 startup

Sets up the application.

=cut
