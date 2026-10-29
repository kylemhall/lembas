package Lembas::Model::Users;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(false true);

use constant COLUMNS => q{
    u.id, u.email, u.name, u.is_active, u.polr_username,
    DATE_FORMAT(u.last_login_at, '%Y-%m-%dT%H:%i:%sZ') AS last_login_at,
    DATE_FORMAT(u.created_at, '%Y-%m-%dT%H:%i:%sZ') AS created_at
};

has [qw(mysql admin_emails)];

sub find ( $self, $id ) { return $self->_find( 'u.id = ?', $id ) }

sub find_by_email ( $self, $email ) { return $self->_find( 'u.email = ?', lc $email ) }

# One statement for the first sign-in and the next ones; an account an admin disabled stays disabled
sub find_or_create_from_claims ( $self, $claims ) {
    $self->mysql->db->query(
        q{
            INSERT INTO users (email, name, google_sub, last_login_at) VALUES (?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE name = VALUES(name), google_sub = VALUES(google_sub), last_login_at = NOW()
        },
        @$claims{qw(email name sub)}
    );
    return $self->find_by_email( $claims->{email} );
}

sub list ($self) {
    my $users = $self->mysql->db->query(
              'SELECT '
            . COLUMNS
            . q{, (SELECT COUNT(*) FROM links l WHERE l.user_id = u.id) AS links_count
            FROM users u ORDER BY u.email}
    )->hashes;
    return [ map { $self->_inflate($_) } @$users ];
}

sub set_active ( $self, $id, $is_active ) {
    return $self->mysql->db->update( users => { is_active => $is_active ? 1 : 0 }, { id => $id } )->rows;
}

sub create_imported ( $self, $user ) { return $self->mysql->db->insert( users => $user )->last_insert_id }

sub _find ( $self, $where, @values ) {
    my $user = $self->mysql->db->query( 'SELECT ' . COLUMNS . " FROM users u WHERE $where", @values )->hash;
    return $user ? $self->_inflate($user) : undef;
}

sub _inflate ( $self, $user ) {
    $user->{is_active} = $user->{is_active}                      ? true : false;
    $user->{is_admin}  = $self->admin_emails->{ $user->{email} } ? true : false;
    return $user;
}

1;

=head1 NAME

Lembas::Model::Users - The people who sign in

=head1 SYNOPSIS

  my $user = $app->users->find_by_email('jane@example.org');

=head1 DESCRIPTION

A user is identified by their email address, in lower case. C<is_admin> comes from C<LEMBAS_ADMIN_EMAILS>, it is not
stored. Dates are ISO 8601 strings in UTC.

=head2 find

The user with this id, or undef.

=head2 find_by_email

The user with this email address, whatever its case, or undef.

=head2 find_or_create_from_claims

Creates the user of the C<email>, C<name> and C<sub> of an OpenID Connect token, or updates their name and last sign-in.

=head2 list

Every user, by email address, with the number of their links in C<links_count>.

=head2 set_active

Enables or disables an account, returns the number of accounts changed.

=head2 create_imported

Adds a user from Polr, returns their id.

=cut
