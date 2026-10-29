package Lembas::Controller::Redirect;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# 302, not 301: browsers would cache a 301, so changes to the long URL and the clicks would never be seen again
sub go ($c) {
    my $link = $c->links->find_by_ending( $c->stash('ending') ) or return $c->reply->not_found;
    return $c->render( 'redirect/gone', status => 410 ) if $link->{is_disabled};

    # Link checkers and previews ask with HEAD: only visits are clicks
    unless ( $c->req->method eq 'HEAD' ) {
        my $headers = $c->req->headers;
        eval {
            $c->clicks->add( $link->{id}, { referer => $headers->referrer, user_agent => $headers->user_agent } );
            1;
        }
            or $c->log->error("Could not record a click on $link->{ending}: $@");
    }
    return $c->redirect_to( $link->{long_url} );
}

1;

=head1 NAME

Lembas::Controller::Redirect - Follow a short link

=head2 go

C<GET /:ending>: redirects to the long URL and records the click (not for a HEAD request). A disabled link is a 410, an unknown one a 404.
A click that cannot be recorded is logged, the redirect happens anyway.

=cut
