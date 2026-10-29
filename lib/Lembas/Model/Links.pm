package Lembas::Model::Links;
use Mojo::Base -base, -signatures;

use Digest::SHA qw(sha256_hex);
use Encode      qw(encode_utf8);
use Mojo::JSON  qw(false true);
use Mojo::URL;
use Lembas::Error;
use Lembas::Model::Endings;

use constant MAX_URL_LENGTH => 8192;
use constant SELECT => q{
    SELECT l.id, l.ending, l.long_url, l.user_id, l.clicks, l.is_disabled, l.is_custom, l.is_api,
        DATE_FORMAT(l.created_at, '%Y-%m-%dT%H:%i:%sZ') AS created_at,
        DATE_FORMAT(l.updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updated_at,
        u.email AS creator_email
    FROM links l LEFT JOIN users u ON u.id = l.user_id
};

has [qw(mysql short_url)];
has ending_length => 6;
has max_attempts  => 5;
has endings       => sub { Lembas::Model::Endings->new };

sub find ( $self, $id ) { return $self->_find( 'l.id = ?', $id ) }

sub find_by_ending ( $self, $ending ) { return $self->_find( 'l.ending = ?', $ending ) }

# Returns the link and whether it is new: shortening a URL again gives the link already made for it
sub create ( $self, $fields ) {
    my $long_url = $self->_valid_url( $fields->{long_url} );
    my %row      = (
        long_url      => $long_url,
        long_url_hash => sha256_hex( encode_utf8($long_url) ),
        user_id       => $fields->{user_id},
        is_api        => $fields->{is_api} ? 1 : 0,
    );
    return ( $self->_create_custom( $fields->{ending}, \%row ), 1 ) if defined $fields->{ending};

    my $existing = $self->find_duplicate( $fields->{user_id}, $long_url );
    return ( $existing,                      0 ) if $existing;
    return ( $self->_create_random( \%row ), 1 );
}

sub find_duplicate ( $self, $user_id, $long_url ) {
    return $self->_find(
        'l.user_id = ? AND l.long_url_hash = ? AND l.is_custom = 0 AND l.is_disabled = 0',
        $user_id, sha256_hex( encode_utf8($long_url) )
    );
}

sub list ( $self, $query ) {
    my ( @where, @values );
    unless ( $query->{all} ) {
        push @where,  'l.user_id = ?';
        push @values, $query->{user_id};
    }
    if ( length $query->{q} ) {
        my $like = '%' . ( $query->{q} =~ s/([\\%_])/\\$1/gr ) . '%';
        push @where, '(l.ending LIKE ? OR l.long_url LIKE ?)';
        push @values, $like, $like;
    }
    my $where = @where ? 'WHERE ' . join( ' AND ', @where ) : q{};

    my $db    = $self->mysql->db;
    my $total = $db->query( "SELECT COUNT(*) FROM links l $where", @values )->array->[0];
    my $links = $db->query(
        SELECT . " $where ORDER BY l.created_at DESC, l.id DESC LIMIT ? OFFSET ?",
        @values, $query->{per_page}, ( $query->{page} - 1 ) * $query->{per_page}
    )->hashes;
    return { links => [ map { $self->_inflate($_) } @$links ], total => $total };
}

sub update ( $self, $id, $fields ) {
    my %changes;
    if ( exists $fields->{long_url} ) {
        my $long_url = $self->_valid_url( $fields->{long_url} );
        %changes = ( long_url => $long_url, long_url_hash => sha256_hex( encode_utf8($long_url) ) );
    }
    $changes{is_disabled} = $fields->{is_disabled} ? 1 : 0 if exists $fields->{is_disabled};
    $self->mysql->db->update( links => \%changes, { id => $id } );
    return $self->find($id);
}

sub remove ( $self, $id ) {
    $self->mysql->db->delete( links => { id => $id } );
    return;
}

sub _find ( $self, $where, @values ) {
    my $link = $self->mysql->db->query( SELECT . " WHERE $where ORDER BY l.id LIMIT 1", @values )->hash;
    return $link ? $self->_inflate($link) : undef;
}

sub _valid_url ( $self, $long_url ) {
    my $url = Mojo::URL->new($long_url);
    return $long_url
        if length $long_url <= MAX_URL_LENGTH
        && ( $url->scheme // q{} ) =~ /\Ahttps?\z/i
        && length( $url->host // q{} );
    Lembas::Error->throw(
        code    => 'invalid_url',
        message => 'The long URL must be an http or https URL of at most ' . MAX_URL_LENGTH . ' characters',
        status  => 400,
    );
}

sub _create_custom ( $self, $ending, $row ) {
    my $endings = $self->endings;
    Lembas::Error->throw(
        code    => 'invalid_ending',
        message => 'An ending is 1 to 64 letters, digits, dashes or underscores',
        status  => 400,
    ) unless $endings->is_valid($ending);
    Lembas::Error->throw( code => 'reserved_ending', message => qq{"$ending" is reserved}, status => 400 )
        if $endings->is_reserved($ending);

    my $id = $self->_insert( { %$row, ending => $ending, is_custom => 1 } );
    Lembas::Error->throw( code => 'ending_taken', message => qq{"$ending" is already taken}, status => 409 ) unless $id;
    return $self->find($id);
}

sub _create_random ( $self, $row ) {
    my $endings = $self->endings;
    for ( 1 .. $self->max_attempts ) {
        my $ending = $endings->random( $self->ending_length );
        next if $endings->is_reserved($ending);
        my $id = $self->_insert( { %$row, ending => $ending } );
        return $self->find($id) if $id;
    }
    Lembas::Error->throw( code => 'no_free_ending', message => 'No free ending was found, try again', status => 500 );
}

# The id of the new link, or nothing when its ending is taken
sub _insert ( $self, $row ) {
    my $id;
    return $id if eval { $id = $self->mysql->db->insert( links => $row )->last_insert_id; 1 };
    my $error = $@;
    die $error unless $error =~ /Duplicate entry/;
    return;
}

sub _inflate ( $self, $link ) {
    $link->{short_url} = $self->short_url . $link->{ending};
    $link->{$_} = $link->{$_} ? true : false for qw(is_disabled is_custom is_api);
    return $link;
}

1;

=head1 NAME

Lembas::Model::Links - The short links

=head1 SYNOPSIS

  my ( $link, $created ) = $app->links->create( { long_url => 'https://example.org/', user_id => 1 } );
  say $link->{short_url};

=head1 DESCRIPTION

A link has an C<ending>, case sensitive, and its C<short_url> is C<LEMBAS_SHORT_URL> followed by it. Errors are thrown
as L<Lembas::Error>.

=head2 find

The link with this id, or undef.

=head2 find_by_ending

The link with this ending, or undef.

=head2 create

Creates a link for C<long_url> and C<user_id>, with C<ending> when given, and returns it with whether it is new. Without
an ending, the link the user already made for this URL is returned when there is one, else a random ending is chosen.

=head2 find_duplicate

The enabled link with a random ending this user made for this URL, or undef.

=head2 list

The links of C<user_id>, or of everybody with C<all>, matching C<q> when given, newest first: C<per_page> of them
from C<page>. Returns C<links> and their C<total>.

=head2 update

Changes the C<long_url> or C<is_disabled> of a link, and returns it.

=head2 remove

Deletes a link and its clicks.

=cut
