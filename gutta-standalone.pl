#!/usr/bin/perl
#
# This is the  standalone gutta irc client.
#
# 

use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use IO::Socket;
use Getopt::Long;
chdir(dirname(__FILE__));
use Gutta::AbstractionLayer;

my $gal = Gutta::AbstractionLayer->new(parse_response => 1);

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

my $sock = new IO::Socket::INET(PeerAddr => $server,
                                PeerPort => $port,
                                Proto => 'tcp') or
                                    die "Can't connect: $!\n";

# Log on to the server.
print $sock "NICK $own_nick\r\n";
print $sock "USER $login 8 * :Gutta Standalone\r\n"; 

# Read lines from the server until it tells us we have connected.
while (my $input = <$sock>) {
    # Check the numerical responses from the server.
    if ($input =~ /004/) {
        # We are now logged in.
        last;
    }
    elsif ($input =~ /433/) {
        die "Nickname is already in use.";
    }
}

# Join the channel.
print $sock "JOIN $channel\r\n";
print "< JOIN $channel\r\n";


# Keep reading lines from the server.
while (my $input = <$sock>)
{
    chop $input;
    if ($input =~ /^PING(.*)$/i) 
    {
        print "PING? PONG\n"; 
        # We must respond to PINGs to avoid being disconnected.
        print $sock "PONG $1\r\n";
    } else {
        # Print the raw line received by the bot.
        print "> $input\n"; 

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
                printf "< %s", $irc_cmd;
                printf $sock "%s", $irc_cmd;
                
            }
        }

    }
}



