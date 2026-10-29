package Lembas::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub home ($c) { return $c->render( 'pages/home', user => $c->current_user ) }

# Under every page that needs a signed-in user: the anonymous go to the sign-in, and come back after it
sub require_user ($c) {
    if ( my $user = $c->current_user ) {
        $c->stash( user => $user );
        return 1;
    }
    $c->redirect_to( $c->url_for('login')->query( return_to => $c->req->url->path->to_string ) );
    return;
}

sub require_admin ($c) {
    return 1 if $c->stash('user')->{is_admin};
    $c->render( 'pages/forbidden', status => 403 );
    return;
}

sub admin ($c) { return $c->render('pages/admin') }

sub link_stats ($c) { return $c->render( 'pages/link', ending => $c->stash('ending') ) }

1;

=head1 NAME

Lembas::Controller::Pages - The pages: HTML shells for the Alpine.js components of public/js/app.js

=head2 home

C</>: the shortener and the links of the user, or the sign-in button.

=head2 require_user

Lets signed-in users through, sends the others to the sign-in.

=head2 require_admin

Lets admins through, tells the others the page is not for them.

=head2 admin

C</admin>: every user and every link.

=head2 link_stats

C</links/:ending>: the stats of a link.

=cut
