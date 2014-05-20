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
use Gutta::AbstractionLayer;

chdir(dirname(__FILE__));
use Log::Log4perl;

my $server;
my $port = 6667;
my $own_nick;
my @channels;
my $workers2start = 4;
my $login;

Log::Log4perl->init("Gutta/Config/Log4perl.conf");
my $log = Log::Log4perl->get_logger();


GetOptions (
        "server=s" => \$server,
          "port=i" => \$port,
          "nick=s" => \$own_nick,
       "channel=s" => \@channels,
 "workers2start=i" => \$workers2start,
         "login=s" => \$login);


#
# "MAIN"
#
#

$login||=$own_nick;


# Start the Gutta::AbstractionLayer.
my $gal = Gutta::AbstractionLayer->new(parse_response => 1,
                                             own_nick => $own_nick);



$log->info("Connecting to server");


my $sock = new IO::Socket::INET(PeerAddr => $server,
                             PeerPort => $port,
                                Proto => 'tcp',
                               ) or
                                    die "Can't connect: $!\n";

$log->info("Logging in to server");
# Log on to the server.
$log->info(" < NICK $own_nick");
print $sock "NICK $own_nick\r\n";
$log->info(" < USER $login 8 * :Gutta Standalone");
print $sock "USER $login 8 * :Gutta Standalone\r\n";

# Read lines from the server until it tells us we have connected.
while (my $message = <$sock>)
{
    $log->info(sprintf " > %s", $message);
    # Check the numerical responses from the server.
    if ($message =~ /004/) {
        # We are now logged in.
        last;
    }
    elsif ($message =~ /433/) {
        die "Nickname is already in use.";
    }
}


$log->info("*** logged in !!");

# Start the plugin responses
async(\&plugin_responses, $sock, $server)->detach;

$log->info("*** staring heartneat thread");
# Start the heart of Gutta.
async(\&heartbeat, $server)->detach;



print "*** Logged in to server, joining channels\n";
# Join the channels.
foreach my $channel (@channels)
{
    print $sock "JOIN $channel\r\n";
    $log->info(" < JOIN $channel");
}

# Keep reading lines from the server.
while (my $message = <$sock>)
{
    chop $message;

    # display what the server says.
    $log->info(" > $message\n");

    if ($message =~ /^PING (.*)$/i)
    {
        # We must respond to PINGs to avoid being disconnected.
        $log->info(" < PONG $1");
        print $sock "PONG $1\r\n";
    } else {
        my @irc_cmds = $gal->process_msg($server,$message);
        foreach my $irc_cmd (@irc_cmds)
        {
            $log->info(sprintf " < %s", $irc_cmd);
            printf $sock "%s", $irc_cmd;
        }
    }
}

sub plugin_responses
{
    # the plugin responses thread function
    # this one dequeues X amount of responses from the plugins
    # and prints to the socket.
    #
    my $sock = shift;
    my $server = shift;
    $log->debug("*** starting plugin_responses thread");
    while (sleep(2))
    {
        eval {
            my @irc_cmds = $gal->plugin_res(4);
            foreach my $irc_cmd (@irc_cmds)
            {
                $log->info(sprintf" < %s", $irc_cmd);
                print $sock $irc_cmd; #TODO rate limiting "human typing speed"
            }
        };
        warn $@ if $@; #TODO fix.
    }
}

sub heartbeat
{
    # this is calling the gal:s heartbeat which then passes along
    # heartbeats to the appropriate plugin thread.
    #
    my $server = shift;
    $log->debug("*** starting heartbeat thread.");

    # first initialise the queues.
    $gal->init_heartbeat_queues($server);
    while (sleep(2))
    {
        eval {
            $gal->heartbeat();
        };
        warn $@ if $@; #TODO fix.
    }
}
