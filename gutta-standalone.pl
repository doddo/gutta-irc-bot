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
use Getopt::Long qw(GetOptionsFromArray);
chdir(dirname(__FILE__));
use Gutta::AbstractionLayer;

my $gal = Gutta::AbstractionLayer->new();

my $server;
my $port;
my $own_nick;
my $channel;
my $login;

GetOptions (
    "server=s" => \$server,
      "port=i" => \$port,
      "nick=s" => \$own_nick,
   "channel=s" => \$channel,
     "login=s" => \$login);


sub parse_input
{
    #parses the input from the server.
    #
    #:doddo_!~doddo@localhost PRIVMSG #test123123 :doddo2000 (2)
    #:irc.the.net 250 gutta :Highest connection count: 3 (9 connections received)  
    #
    $_ = shift;

    m/^:([^:]+):(.+)$/;
    my $context = $1;
    my $msg = $2;

     

    my ($sender, $msgtype, $target) = split(" ", $context);
    return ($sender, $msgtype, $target, $msg);
}


#

#  MAIN
#
#

my $sock = new IO::Socket::INET(PeerAddr => $server,
                                PeerPort => $port,
                                Proto => 'tcp') or
                                    die "Can't connect\n";

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


# Keep reading lines from the server.
while (my $input = <$sock>)
 {
    chop $input;
    if ($input =~ /^PING(.*)$/i) {
        # We must respond to PINGs to avoid being disconnected.
        print $sock "PONG $1\r\n";
    }
    else {
        # Print the raw line received by the bot.
        print "> $input\n"; 

        # parse the input and decide what to do

        my  ($sender, $msgtype, $target, $msg) = parse_input($input);
       
        # check if it is from a user (nick!address)
        my ($nick, $address) = split ('!', $sender);
        

        if ($nick and $msgtype eq "PRIVMSG" and $nick ne $own_nick)
        {
            # is the message from a nick?
            #  (looks like this: "doddo_!~doddo@localhost"...)
            #  
            my @irc_cmds = $gal->process_msg(
                $server,
                $msg, 
                $nick, 
                $address,  
                $target, 
            );
   
            foreach my $irc_cmd (@irc_cmds)
            {
                $irc_cmd =~ s/^msg (\S+) /PRIVMSG $1 :/i; #GOt TODO something about this
                printf "< %s\r\n", $irc_cmd;
                printf $sock "%s\r\n", $irc_cmd;
                
            }
        }
    }
}



