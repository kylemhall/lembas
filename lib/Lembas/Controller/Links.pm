package Lembas::Controller::Links;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Time::Piece;
use Time::Seconds qw(ONE_DAY);
use Lembas::Error;

use constant MAX_DAYS => 365;

sub list ($self) {
    my $c     = $self->openapi->valid_input or return;
    my $input = $c->validation->output;
    my $user  = $c->stash('user');
    return $c->render_error(
        Lembas::Error->new( code => 'forbidden', message => 'Only admins can list every link', status => 403 ) )
        if $input->{all} && !$user->{is_admin};

    my $result = $c->links->list( { %$input{qw(q page per_page all)}, user_id => $user->{id} } );
    return $c->render( openapi => { %$result, page => $input->{page}, per_page => $input->{per_page} } );
}

sub create ($self) {
    my $c    = $self->openapi->valid_input or return;
    my $body = $c->req->json;
    my ( $link, $created );
    eval {
        ( $link, $created ) = $c->links->create(
            {
                long_url => $body->{long_url},
                ending   => $body->{ending},
                user_id  => $c->stash('user')->{id},
                is_api   => $c->stash('lembas.api_key'),
            }
        );
        1;
    } or return $c->render_error($@);
    return $c->render( openapi => $link, status => $created ? 201 : 200 );
}

sub show ($self) {
    my $c    = $self->openapi->valid_input or return;
    my $link = $c->_owned_link             or return;
    return $c->render( openapi => $link );
}

sub update ($self) {
    my $c    = $self->openapi->valid_input or return;
    my $link = $c->_owned_link             or return;
    eval { $link = $c->links->update( $link->{id}, $c->req->json ); 1 } or return $c->render_error($@);
    return $c->render( openapi => $link );
}

sub remove ($self) {
    my $c    = $self->openapi->valid_input or return;
    my $link = $c->_owned_link             or return;
    $c->links->remove( $link->{id} );
    return $c->rendered(204);
}

sub stats ($self) {
    my $c     = $self->openapi->valid_input or return;
    my $link  = $c->_owned_link             or return;
    my $input = $c->validation->output;

    my $to   = _day( defined $input->{to} ? $input->{to} : Time::Piece::gmtime()->ymd );
    my $from = defined $input->{from} ? _day( $input->{from} ) : $to - 29 * ONE_DAY;
    return $c->render_error(
        Lembas::Error->new(
            code    => 'invalid_period',
            message => '"from" must be a day before "to", at most ' . MAX_DAYS . ' days before',
            status  => 400
        )
    ) if $from > $to || $to - $from > MAX_DAYS * ONE_DAY;

    my $stats = $c->clicks->stats( $link->{id}, $from->ymd, $to->ymd );
    return $c->render( openapi => { ending => $link->{ending}, from => $from->ymd, to => $to->ymd, %$stats } );
}

sub _day ($ymd) { return Time::Piece->strptime( $ymd, '%Y-%m-%d' ) }

# The link of the path when the user may see it: renders a 404 or a 403 and returns nothing otherwise
sub _owned_link ($c) {
    my $user = $c->stash('user');
    my $link = $c->links->find_by_ending( $c->validation->output->{ending} );
    unless ($link) {
        $c->render_error( Lembas::Error->new( code => 'not_found', message => 'No such link', status => 404 ) );
        return;
    }
    return $link if $user->{is_admin} || ( $link->{user_id} // 0 ) == $user->{id};
    $c->render_error(
        Lembas::Error->new( code => 'forbidden', message => 'This link belongs to someone else', status => 403 ) );
    return;
}

1;

=head1 NAME

Lembas::Controller::Links - The links, in the REST API

=head1 DESCRIPTION

Users see and change their own links, admins every link. See F<api/lembas.yaml>.

=head2 list

C<GET /api/v1/links>

=head2 create

C<POST /api/v1/links>

=head2 show

C<GET /api/v1/links/{ending}>

=head2 stats

C<GET /api/v1/links/{ending}/stats>

=head2 update

C<PATCH /api/v1/links/{ending}>

=head2 remove

C<DELETE /api/v1/links/{ending}>

=cut
