package Lembas::Controller::Health;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub health ($c) { return $c->render( json => { status => 'ok' } ) }

sub ready ($c) {
    my $migrations = $c->app->mysql->migrations;
    my ( $active, $latest );
    unless ( eval { ( $active, $latest ) = ( $migrations->active, $migrations->latest ); 1 } ) {
        $c->log->warn("Not ready, the database cannot be reached: $@");
        return $c->render( json => { status => 'unavailable', reason => 'db' }, status => 503 );
    }
    return $c->render( json => { status => 'unavailable', reason => 'migrations_pending' }, status => 503 )
        if $active != $latest;
    return $c->render( json => { status => 'ok' } );
}

1;

=head1 NAME

Lembas::Controller::Health - The probes of the container

=head1 DESCRIPTION

C</health> tells that the process answers (liveness), C</ready> that it can serve: the database answers and every
migration is applied. A deployment that forgot C<script/lembas migrate> never becomes ready.

=head2 health

Always C<{"status":"ok"}>.

=head2 ready

C<{"status":"ok"}>, or a 503 with the reason: C<db> or C<migrations_pending>.

=cut
