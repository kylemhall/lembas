package Lembas::Model::ApiKeys;
use Mojo::Base -base, -signatures;

use Crypt::PRNG qw(random_string);
use Digest::SHA qw(sha256_hex);

use constant PREFIX => 'lmb_';
use constant COLUMNS => q{
    id, label, key_prefix,
    DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS created_at,
    DATE_FORMAT(last_used_at, '%Y-%m-%dT%H:%i:%sZ') AS last_used_at
};

has 'mysql';

sub hash_key ( $class, $key ) { return sha256_hex($key) }

sub create ( $self, $user_id, $label ) { return $self->_add( $user_id, $label, PREFIX . random_string(40) ) }

# The keys of Polr keep working
sub import_key ( $self, $user_id, $label, $key ) { return $self->_add( $user_id, $label, $key ) }

sub list ( $self, $user_id ) {
    return $self->mysql->db->query( 'SELECT ' . COLUMNS . ' FROM api_keys WHERE user_id = ? ORDER BY id', $user_id )
        ->hashes->to_array;
}

sub revoke ( $self, $user_id, $id ) {
    return $self->mysql->db->delete( api_keys => { id => $id, user_id => $user_id } )->rows;
}

sub is_known ( $self, $key ) {
    return !!$self->mysql->db->select( api_keys => 'id', { key_hash => $self->hash_key($key) } )->rows;
}

# The id of the active user of the key, or nothing
sub authenticate ( $self, $key ) {
    my $db    = $self->mysql->db;
    my $found = $db->query(
        q{
            SELECT k.id, k.user_id FROM api_keys k JOIN users u ON u.id = k.user_id
            WHERE k.key_hash = ? AND u.is_active = 1
        },
        $self->hash_key($key)
    )->hash or return;
    $db->query( 'UPDATE api_keys SET last_used_at = NOW() WHERE id = ?', $found->{id} );
    return $found->{user_id};
}

# The key itself is only in what this returns: the database keeps its hash
sub _add ( $self, $user_id, $label, $key ) {
    my $db = $self->mysql->db;
    my $id = $db->insert(
        api_keys => {
            user_id    => $user_id,
            label      => $label,
            key_prefix => substr( $key, 0, 12 ),
            key_hash   => $self->hash_key($key)
        }
    )->last_insert_id;
    return { %{ $db->query( 'SELECT ' . COLUMNS . ' FROM api_keys WHERE id = ?', $id )->hash }, key => $key };
}

1;

=head1 NAME

Lembas::Model::ApiKeys - The API keys of the users

=head1 SYNOPSIS

  my $api_key = $app->api_keys->create( $user->{id}, 'Deploy script' );
  say $api_key->{key};    # shown once

  my $user_id = $app->api_keys->authenticate($key);

=head1 DESCRIPTION

A user can have several keys. Only the SHA-256 hash of a key and its first 12 characters (C<key_prefix>, to recognize
it) are stored.

=head2 hash_key

The hash stored for a key.

=head2 create

A new key for a user, with a label. The returned C<key> is the only time the key is seen.

=head2 import_key

Adds a key that exists elsewhere, like an API key of Polr.

=head2 list

The keys of a user, without the keys themselves.

=head2 revoke

Deletes a key of a user, returns the number of keys deleted.

=head2 is_known

Whether this key exists, for any user.

=head2 authenticate

The id of the user of the key when the user is active, or nothing. Records when the key was last used.

=cut
