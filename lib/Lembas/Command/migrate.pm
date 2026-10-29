package Lembas::Command::migrate;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(getopt);

has description => 'Apply the database migrations';
has usage       => sub ($self) { $self->extract_usage };

sub run ( $self, @args ) {
    getopt( \@args, 'to=i' => \my $to, status => \my $status ) or die $self->usage;

    my $migrations = $self->app->mysql->migrations;
    my ( $active, $latest ) = ( $migrations->active, $migrations->latest );
    say "Database version $active, latest $latest";
    return if $status;

    $to = $latest unless defined $to;
    die "--to must be between 0 and $latest\n" if $to < 0 || $to > $latest;
    $migrations->migrate($to);
    say "Migrated from version $active to $to";
    return;
}

1;

=head1 NAME

Lembas::Command::migrate - Apply the database migrations

=head1 SYNOPSIS

  Usage: script/lembas migrate [OPTIONS]

    script/lembas migrate            # to the latest version
    script/lembas migrate --status   # show the versions, change nothing
    script/lembas migrate --to 0     # down to an empty database

  Options:
    --to <version>   Migrate up or down to this version of migrations/lembas.sql
    --status         Only show the current and the latest version

=head1 DESCRIPTION

Migrations are never applied when the web server starts: run this before deploying a version with new migrations.
MariaDB commits every schema change at once, so a migration that fails half way leaves a partial schema: look at the
database before running it again.

=head2 run

Runs the command.

=cut
