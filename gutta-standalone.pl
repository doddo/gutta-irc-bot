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
use Gutta::Constants;

use Log::Log4perl;
#Log::Log4perl->init(Gutta::Constants::LOG4PERLCONF);

use Gutta::AbstractionLayer;

chdir(dirname(__FILE__));
use Pod::Usage;


=head1 NAME
gutta-standalone.pl 
=head1 SYNOPSIS
$0 --server SERVER --nick NICK  [options] 

=head1 OPTIONS

=over 8

=item B<--server>

The irc server to connect to

=item B<--port>

What port to use when connecting to server

=item B<--nick>

What nick to use

=item B<--channel>

What channel to join. Multiple channels can be specified by adding multiple --channel flags. Remember to escape the \# if your shell might interpret it.

=back

=head1 DESCRIPTION

B<This program> is the gutta irc bot starter. Use it with the flags to connect to a server.

=cut

my $server;
my $port = 6667;
my $own_nick;
my @channels;
my $login;
my $help = 0;

my $log = Log::Log4perl->get_logger();


GetOptions (
        "server=s" => \$server,
          "port=i" => \$port,
          "nick=s" => \$own_nick,
       "channel=s" => \@channels,
            "help" => \$help,
         "login=s" => \$login) 
   or pod2usage(0);

if ($help)
{ 
  print "KALLE\n";
  pod2usage(1);
  exit(0);
}


#
# "MAIN"
#
#

$login||=$own_nick;


$log->info("Now starting Gutta irc bot.");


# Start the Gutta::AbstractionLayer.
my $gal = Gutta::AbstractionLayer->new(parse_response => 1,
                                             own_nick => $own_nick);



$log->info("Connecting to server");


my $sock = new IO::Socket::INET(PeerAddr => $server,
                             PeerPort => $port,
                                Proto => 'tcp',
                               ) or
                                    die "Can't connect: $!\n";

# Handle what happens on sigINT
$SIG{INT} = \&clean_shutdown_stub;


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

                # check that the quit msg've been sent to the server. If that's the case
                # then exit the plugin_responses thread.
                last if $irc_cmd =~ /^QUIT/;
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

# Trap Ctrl+C etc...
sub clean_shutdown_stub {
    my $signame = shift;
    my $quitmsg = "Gone to have lunch";
    $log->info("SHUTTING DOWN EVERYTHING FROM A SIG${signame}");
    $gal->quit_irc($quitmsg);
    sleep 2;
}
