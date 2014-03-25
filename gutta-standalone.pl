#!/usr/bin/perl
#
# This is the plain standalone gutta irc client.
#  it just connects to --server using --nick and joins --channel.
# Then it will pass along all the messages through the Gutta::Abstractionlayer
# which interfaces with the plugins.
# 

use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use IO::Socket;
use Getopt::Long;
use threads;
use threads::shared;

chdir(dirname(__FILE__));
use Gutta::AbstractionLayer;

my $server;
my $port = 6667;
my $own_nick;
my $channel;
my $login;

GetOptions (
    "server=s" => \$server,
      "port=i" => \$port,
      "nick=s" => \$own_nick,
   "channel=s" => \$channel,
     "login=s" => \$login);


#
#  MAIN
#
#

$login||=$own_nick;


my $gal = Gutta::AbstractionLayer->new(parse_response => 1);

# set commandprefix:
$gal->set_cmdprefix(qr/(${own_nick}[.:]\s+|[!])/);



print "Connecting to server\n";


my $sock = new IO::Socket::INET(PeerAddr => $server,
                             PeerPort => $port,
                                Proto => 'tcp',
                               ) or
                                    die "Can't connect: $!\n";

print "*** Logging in to server\n";
# Log on to the server.
print $sock "NICK $own_nick\r\n";
print $sock "USER $login 8 * :Gutta Standalone\r\n"; 

# Read lines from the server until it tells us we have connected.
while (my $input = <$sock>) 
{
    printf " >%s", $input;
    # Check the numerical responses from the server.
    if ($input =~ /004/) {
        # We are now logged in.
        last;
    }
    elsif ($input =~ /433/) {
        die "Nickname is already in use.";
    }
}


print "*** logged in !!\n";

# Start the heartbeat thread
async(\&heartbeat, $sock, $server)->detach;

print "*** Logged in to server, joining channels\n";
# Join the channel.
print $sock "JOIN $channel\r\n";
print " < JOIN $channel\r\n";


# Keep reading lines from the server.
while (my $input = <$sock>)
{
    chop $input;
    if ($input =~ /^PING(.*)$/i) 
    {
        print "PING? PONG!\n"; 
        # We must respond to PINGs to avoid being disconnected.
        print $sock "PONG $1\r\n";
    } else {
        # Print the raw line received by the bot.
        print " > $input\n"; 

        # ITS A PRIVMSG 
        if ($input =~ m/^:[^:]+ PRIVMSG/)
        {
            # PARSE THE PRIVMSG...
            my ($msg, $nick, $mask, $target) = $gal->parse_privmsg($input);
            warn "parsing fiald for $msg $nick $mask $target\n";

            # ...and run resulting cmds (if any)
            my @irc_cmds = $gal->process_msg($server, $msg, $nick, $mask, $target);       
            foreach my $irc_cmd (@irc_cmds)
            {
                printf " < %s", $irc_cmd;
                printf $sock "%s", $irc_cmd;
                
            }
        }
    }
}

sub heartbeat
{
    # the heartbeat therad sub function.
    # on an interval of 3 seconds, send a heartbeat to all of the
    # plugins heartbeat methods trhough Gutta::Abstractionlayer.
    # 
    #
    my $sock = shift;
    my $server = shift;
    print "*** starting heartbeat thread\n";
    while (sleep(3))
    { 
        $gal->heartbeat();
        my @irc_cmds = $gal->heartbeat_res($server);
        foreach my $irc_cmd (@irc_cmds)
        {
            printf "♥< %s", $irc_cmd;
            print $sock $irc_cmd;
        }
    }
}
