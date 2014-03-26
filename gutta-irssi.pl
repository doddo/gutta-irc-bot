#
# This is guttas Irssi interface.
# it speaks through the Gutta::AbstractionLayer with  plugins
# and sends processed responses to irssi.
#
# == INSTALL
# Save the whole thing under ~/.irssi/scripts/ and then  you can
# load it from irssi.
# 

use strict;
use warnings;
use Irssi;
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use File::Basename;
chdir(dirname(__FILE__));
use Gutta::AbstractionLayer;

my $gal = Gutta::AbstractionLayer->new();

$VERSION = '0.1';
%IRSSI = (
    authors => 'Petter H',
    name => 'gutta',
    description => 'Guta bot',
    license => 'GPL',
);

sub process_msg
{
    my $server = shift; # the IRC server
    my $msg = shift;    # The message
    my $nick = shift;   # who sent it?
    my $mask = shift;   # the hostmask of who sent it
    my $target = shift||$nick; # for privmsgs, the target (a channel)
 
    my @irc_cmds = $gal->process_msg(
        $server,
        $msg, 
        $nick, 
        $mask,  
        $target, 
    );
    Irssi::print  Dumper(@irc_cmds);
    Irssi::print "a new message have arrived.";
    Irssi::print join (" ", @_);
    foreach my $irc_cmd (@irc_cmds)
    {
        Irssi::print (sprintf 'trying %s', $irc_cmd);
        $server->command($irc_cmd);
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
        process_msg($server, $msg, $nick, $mask, $target); # if $nick ne $server->{nick};
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
        process_msg($server, $msg, $nick, $address);
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

