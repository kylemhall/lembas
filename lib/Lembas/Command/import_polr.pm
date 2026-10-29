package Lembas::Command::import_polr;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(getopt);
use Mojo::mysql;
use Lembas::Model::PolrImport;

has description => 'Copy the users, links and clicks of a Polr database';
has usage       => sub ($self) { $self->extract_usage };

sub run ( $self, @args ) {
    getopt( \@args, 'from=s' => \my $from, 'password-file=s' => \my $password_file, 'dry-run' => \my $dry_run )
        or die $self->usage;
    die $self->usage unless defined $from;

    my $polr = Mojo::mysql->new($from);
    $polr->password( path($password_file)->slurp =~ s/\r?\n\z//r ) if defined $password_file;
    my $app     = $self->app;
    my $summary = Lembas::Model::PolrImport->new(
        polr           => $polr,
        mysql          => $app->mysql,
        allowed_domain => $app->config->{allowed_domain},
    )->run( { dry_run => $dry_run } );

    my %s = %$summary;
    say "Endings in Polr: $s{collation}"
        . ( $s{collation} =~ /_ci\z/ ? ', case insensitive: in Lembas they are case sensitive' : q{} );
    say "Users: $s{users_created} created, $s{users_existing} already in Lembas";
    say 'Polr admins, to add to LEMBAS_ADMIN_EMAILS: ', join( ', ', @{ $s{admins} } ) if @{ $s{admins} };
    say "API keys: $s{api_keys_imported} imported";
    say "API keys left out: $_" for @{ $s{api_keys_skipped} };
    say "Links: $s{links_created} created, $s{links_existing} already in Lembas, $s{links_anonymous} without a user";
    say 'Links too long to import: ', join( ', ', @{ $s{links_too_long} } ) if @{ $s{links_too_long} };
    say 'Secret links, now public: ', join( ', ', @{ $s{secret_links} } )   if @{ $s{secret_links} };
    say "Clicks: $s{clicks}";
    say 'Dry run: nothing was written' if $dry_run;
    return;
}

1;

=head1 NAME

Lembas::Command::import_polr - Copy the users, links and clicks of a Polr database

=head1 SYNOPSIS

  Usage: script/lembas import_polr --from URL [OPTIONS]

    script/lembas import_polr --from mariadb://polr@172.20.24.33/polr --password-file /run/secrets/polr --dry-run
    script/lembas import_polr --from mariadb://polr@172.20.24.33/polr --password-file /run/secrets/polr

  Options:
    --from <URL>             The Polr database, mariadb://user@host/database
    --password-file <file>   The password of that user, kept out of the process list
    --dry-run                Count what would be imported, write nothing

=head1 DESCRIPTION

Runs as often as needed: users already in Lembas (by email address) and links already in Lembas (by ending) are left
alone. See L<Lembas::Model::PolrImport> for what is copied.

=head2 run

Runs the command.

=cut
