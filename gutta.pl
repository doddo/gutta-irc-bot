# == WHAT
# All around bot "Gutta".
#
# == WHO
# Based on "All around bot" by Jeroen Van den Bossche, 2012
# Fork By PETTER H 2014
#
# == INSTALL
# Save the whole thing under ~/.irssi/scripts/ and then run irssi, and /load gutta.pl
# OR
# Save it in ~/.irssi/scripts/autorun and (re)start Irssi

use strict;
use warnings;
use Irssi;
use vars qw($VERSION %IRSSI);

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';
use File::Basename;
chdir(dirname(__FILE__));

use Data::Dumper;

$VERSION = '0.1';
%IRSSI = (
    authors => 'Petter H',
    name => 'gutta',
    description => 'All around Irssi bots brother gutta.',
    license => 'GPL',
);

sub process_message 
{
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $target = shift;
    my $save;


    if ($msg =~ m/!plugins/)
    {
        $server->command("msg $target INSTALLED PLUGINS:");
        $server->command("msg $target " . ref $_) foreach plugins();
        return;
    }

    foreach my $plugin (plugins()) 
    {
        foreach($plugin->process_msg($msg, $nick))
        {
            next if not $_;
            warn("calling plugin $plugin");
            $server->command("msg $target " . $_); 
        }
    }
}

Irssi::signal_add_last('message public', sub {
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    Irssi::signal_continue($server, $msg, $nick, $mask, $target);
    eval {
        process_message($server, $msg, $nick, $target) if $nick ne $server->{nick};
    };
    warn ($@) if $@;
});

Irssi::timeout_add(6000, sub {
    Irssi::print("heartbeat from gutta");
    foreach my $server (Irssi::servers())
    {
        #warn Dumper($server);
    }

}, undef);



=pod
Irssi::signal_add_last('message own_public', sub {
    my ($server, $msg, $target) = @_;
    Irssi::signal_continue($server, $msg, $target);
    process_message($server, $msg,$target);
});
=cut
