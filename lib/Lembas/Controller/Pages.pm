package Lembas::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub home ($c) { return $c->render( 'pages/home', user => $c->current_user ) }

1;

=head1 NAME

Lembas::Controller::Pages - The pages: HTML shells for the Alpine.js components of public/js/app.js

=head2 home

C</>: the shortener and the links of the user, or the sign-in button.

=cut
