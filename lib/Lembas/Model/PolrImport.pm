package Lembas::Model::PolrImport;
use Mojo::Base -base, -signatures;

use Digest::SHA qw(sha256_hex);
use Encode      qw(encode_utf8);
use Lembas::Model::ApiKeys;

# The bytes of a TEXT column
use constant MAX_URL_BYTES => 65_535;

has [qw(polr mysql allowed_domain)];

# Everything in one transaction: a dry run is rolled back, a failed import leaves nothing behind
sub run ( $self, $options ) {
    my %summary = (
        users_created     => 0,
        users_existing    => 0,
        admins            => [],
        api_keys_imported => 0,
        api_keys_skipped  => [],
        links_created     => 0,
        links_existing    => 0,
        links_anonymous   => 0,
        links_too_long    => [],
        secret_links      => [],
        clicks            => 0,
    );
    my $db = $self->mysql->db;
    my $tx = $db->begin;
    $summary{collation} = $self->polr->db->query(
        q{
            SELECT COLLATION_NAME FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'links' AND COLUMN_NAME = 'short_url'
        }
    )->array->[0];

    my $user_ids = $self->_import_users( $db, \%summary );
    $self->_import_links( $db, $user_ids, \%summary );
    $tx->commit unless $options->{dry_run};
    return \%summary;
}

# The Lembas user of every Polr username
sub _import_users ( $self, $db, $summary ) {
    my %user_ids;
    my $users = $self->polr->db->query(
        q{
            SELECT username, email, role, active, api_key, api_active, COALESCE(created_at, NOW()) AS created_at
            FROM users ORDER BY id
        }
    )->hashes;
    for my $user (@$users) {
        my $email     = lc( $user->{email} =~ s/\A\s+|\s+\z//gr );
        my $is_active = $user->{active} eq '1' ? 1 : 0;
        push @{ $summary->{admins} }, $email if $user->{role} eq 'admin';

        my $existing = $db->select( users => 'id', { email => $email } )->array;
        if ($existing) {
            $user_ids{ $user->{username} } = $existing->[0];
            $summary->{users_existing}++;
        } else {
            $user_ids{ $user->{username} } = $db->insert(
                users => {
                    email         => $email,
                    polr_username => $user->{username},
                    is_active     => $is_active,
                    created_at    => $user->{created_at}
                }
            )->last_insert_id;
            $summary->{users_created}++;
        }
        $self->_import_api_key(
            $db, $summary,
            {
                user_id => $user_ids{ $user->{username} }, email => $email, is_active => $is_active,
                key     => $user->{api_key}
            }
        ) if $user->{api_active} && length $user->{api_key};
    }
    return \%user_ids;
}

# Their scripts keep working through the Polr API of Lembas, for the accounts that can still sign in
sub _import_api_key ( $self, $db, $summary, $owner ) {
    my ( $email, $domain ) = ( $owner->{email}, $self->allowed_domain );
    my $hash = Lembas::Model::ApiKeys->hash_key( $owner->{key} );
    my $reason =
          $email !~ /\@\Q$domain\E\z/                                  ? "not $domain"
        : !$owner->{is_active}                                         ? 'disabled'
        : $db->select( api_keys => 'id', { key_hash => $hash } )->rows ? 'already imported'
        :                                                                undef;
    if ( defined $reason ) {
        push @{ $summary->{api_keys_skipped} }, "$email ($reason)";
        return;
    }
    $db->insert(
        api_keys => {
            user_id    => $owner->{user_id},
            label      => 'Imported from Polr',
            key_prefix => substr( $owner->{key}, 0, 12 ),
            key_hash   => $hash
        }
    );
    $summary->{api_keys_imported}++;
    return;
}

sub _import_links ( $self, $db, $user_ids, $summary ) {
    my $polr  = $self->polr->db;
    my $links = $polr->query(
        q{
            SELECT id, short_url, long_url, creator, clicks, secret_key, is_disabled, is_custom, is_api,
                COALESCE(created_at, NOW()) AS created_at, COALESCE(updated_at, created_at, NOW()) AS updated_at
            FROM links ORDER BY id
        }
    )->hashes;
    for my $link (@$links) {
        my $ending = $link->{short_url};
        if ( $db->select( links => 'id', { ending => $ending } )->rows ) {
            $summary->{links_existing}++;
            next;
        }
        my $long_url = encode_utf8( $link->{long_url} );
        if ( length $long_url > MAX_URL_BYTES ) {
            push @{ $summary->{links_too_long} }, $ending;
            next;
        }

        # Anonymous links have no user: '' from the web form of Polr, ANONIP-<address> from its API
        my $user_id = $user_ids->{ $link->{creator} };
        $summary->{links_anonymous}++ unless defined $user_id;
        push @{ $summary->{secret_links} }, $ending if length $link->{secret_key};

        my $link_id = $db->insert(
            links => {
                ending        => $ending,
                long_url      => $link->{long_url},
                long_url_hash => sha256_hex($long_url),
                user_id       => $user_id,
                %$link{qw(clicks is_disabled is_custom is_api created_at updated_at)},
            }
        )->last_insert_id;
        my $clicks = $polr->query(
            q{
                SELECT COALESCE(created_at, NOW()) AS clicked_at, referer, referer_host, LEFT(user_agent, 512) AS user_agent
                FROM clicks WHERE link_id = ? ORDER BY id
            },
            $link->{id}
        )->hashes;
        $db->insert( clicks => { link_id => $link_id, %$_ } ) for @$clicks;
        $summary->{clicks} += @$clicks;
        $summary->{links_created}++;
    }
    return;
}

1;

=head1 NAME

Lembas::Model::PolrImport - Copy the users, links and clicks of Polr

=head1 SYNOPSIS

  my $summary = Lembas::Model::PolrImport->new(
      polr           => Mojo::mysql->new('mariadb://polr@db/polr'),
      mysql          => $app->mysql,
      allowed_domain => 'example.org',
  )->run( { dry_run => 1 } );

=head1 DESCRIPTION

Users are matched by email address, links by ending: what is already in Lembas is left alone, so the import can run
again. The endings, long URLs, counters, flags and dates of the links are kept, and so are the clicks, without their
IP addresses and countries. Secret links become public links. The Polr admins are only listed: admins come from
C<LEMBAS_ADMIN_EMAILS>.

=head2 run

Imports, or with C<dry_run> only counts, and returns what it did: C<users_created>, C<users_existing>, C<admins>,
C<api_keys_imported>, C<api_keys_skipped>, C<links_created>, C<links_existing>, C<links_anonymous>, C<links_too_long>,
C<secret_links>, C<clicks>, and the C<collation> of the endings in Polr.

=cut
