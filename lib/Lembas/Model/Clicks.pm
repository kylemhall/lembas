package Lembas::Model::Clicks;
use Mojo::Base -base, -signatures;

use List::Util qw(sum0);
use Mojo::URL;

# The sizes of the columns
use constant MAX_LENGTH => { referer => 2048, referer_host => 255, user_agent => 512 };

has 'mysql';

# The counter is incremented by the database: concurrent clicks are never lost
sub add ( $self, $link_id, $request ) {
    my $referer = $request->{referer};
    my %click   = (
        referer      => $referer,
        referer_host => defined $referer ? Mojo::URL->new($referer)->host : undef,
        user_agent   => $request->{user_agent},
    );
    for my $column ( keys %click ) {
        $click{$column} = substr $click{$column}, 0, MAX_LENGTH->{$column} if defined $click{$column};
    }

    my $db = $self->mysql->db;
    my $tx = $db->begin;
    $db->insert( clicks => { link_id => $link_id, %click } );
    $db->query( 'UPDATE links SET clicks = clicks + 1 WHERE id = ?', $link_id );
    $tx->commit;
    return;
}

sub stats ( $self, $link_id, $from, $to ) {
    my $db     = $self->mysql->db;
    my @period = ( $link_id, $from, $to );
    my $days   = $db->query(
        q{
            SELECT DATE_FORMAT(clicked_at, '%Y-%m-%d') AS day, COUNT(*) AS clicks
            FROM clicks WHERE link_id = ? AND clicked_at >= ? AND clicked_at < ? + INTERVAL 1 DAY
            GROUP BY day ORDER BY day
        },
        @period
    )->hashes->to_array;
    my $referers = $db->query(
        q{
            SELECT COALESCE(referer_host, '') AS host, COUNT(*) AS clicks
            FROM clicks WHERE link_id = ? AND clicked_at >= ? AND clicked_at < ? + INTERVAL 1 DAY
            GROUP BY host ORDER BY clicks DESC, host LIMIT 10
        },
        @period
    )->hashes->to_array;
    return { total => sum0( map { $_->{clicks} } @$days ), clicks_per_day => $days, top_referers => $referers };
}

1;

=head1 NAME

Lembas::Model::Clicks - The clicks on the links

=head1 SYNOPSIS

  $app->clicks->add( $link->{id}, { referer => $referer, user_agent => $user_agent } );
  my $stats = $app->clicks->stats( $link->{id}, '2026-10-01', '2026-10-31' );

=head1 DESCRIPTION

A click keeps its time, its referer and the host of its referer, and its user agent. No IP address.

=head2 add

Records a click on a link and adds it to the C<clicks> of the link.

=head2 stats

The clicks of a link between two days, both included, in UTC: their C<total>, C<clicks_per_day> (C<day>, C<clicks>)
and the ten C<top_referers> (C<host>, C<clicks>; an empty host is a direct visit).

=cut
