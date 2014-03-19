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
use Data::Dumper;
use File::Basename;

chdir(dirname(__FILE__));
use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';

my @PLUGINS  = plugins();

warn "loaded plugin ", ref $_ foreach @PLUGINS;

$VERSION = '0.1';
%IRSSI = (
    authors => 'Petter H',
    name => 'gutta',
    description => 'All around Irssi bots brother gutta.',
    license => 'GPL',
);

sub process_msg
{
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;

    foreach my $plugin (@PLUGINS)
    {
        foreach my $command ($plugin->process_msg($msg, $nick, $mask, $target))
        {
            if ($command)
            {
                Irssi::print("running command: '$command' on behalf of " . ref $plugin);
                $server->command($command);
            }
        }
    }
}

sub process_privmsg
{
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $address = shift;

    foreach my $plugin (@PLUGINS)
    {
        foreach my $command ($plugin->process_privmsg($msg, $nick, $address))
        {
            if ($command)
            {
                Irssi::print("running command: '$command' on behalf of " . ref $plugin);
                $server->command($command);
            }
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
        process_msg($server, $msg, $nick, $mask, $target) if $nick ne $server->{nick};
    };
    warn ($@) if $@;
});

Irssi::signal_add_last('message private', sub {
    #  "message private", SERVER_REC, char *msg, char *nick, char *address
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $address = shift;
    Irssi::print(join " ", ($server, $msg, $nick, $address));
    Irssi::signal_continue($server, $msg, $nick, $address);
    eval {
        process_privmsg($server, $msg, $nick, $address);
    };
    warn ($@) if $@;
});

Irssi::timeout_add(2142, sub {
    # This will call plugins heartbeats method  on a 2142 ms interval.
    # then for each connected server, it will call heartbeat_res -
    # method, and execute what ever command the plugin returned.
    #Irssi::print("heartbeat from gutta");

    if (Irssi::servers())
    {
        eval {
            $_->heartbeat() foreach (@PLUGINS);
            foreach my $server (Irssi::servers())
            {
                # dont act when server is not connected
                next unless $server->{connected};

                #warn Dumper($server);
                foreach my $plugin (@PLUGINS)
                {
                    foreach my $command ($plugin->heartbeat_res($server->{address}))
                    {
                        Irssi::print("got '$command' from ". ref $plugin) if $command;
                        $server->command($command) if $command;
                    }
                }
            }
        };
        Irssi:print($@) if $@;
    } else {
        Irssi::print("not passing heartbeats to plugins because not connected");
    }

}, undef);
