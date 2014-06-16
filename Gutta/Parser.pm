#!/usr/bin/perl
package Gutta::Parser;
use strict;
use warnings;
use Data::Dumper;
use Log::Log4perl;

=head1 NAME

Gutta::Parser

=head1 SYNOPSIS

Parse and format messages to and from IRC server and Gutta::Plugins through Gutta::AbstractionLayer..

=head1 DESCRIPTION

Messages from the IRC server gets parsed using the  Gutta::Parser, so that Gutta::AbstractionLayer knows what to to with them,

In addition to that, once a MSG have been recieved from the Plugins, the Gutta::Parser translate them to a format which makes sense to the IRC server.

=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);


sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
    }, $class;


    # load commands and triggers from plugins
    %{$self->{parsers}} = ( 
         'PRIVMSG' => sub { $self->parse_privmsg(@_) },
             '353' => sub { $self->parse_353_nicks(@_) },
             '366' => sub { $self->parse_366_end_of_names(@_) },
            'JOIN' => sub { $self->parse_joined_channel(@_) },
            'PART' => sub { $self->parse_parted_channel(@_) },
            'QUIT' => sub { $self->parse_userquit(@_) },
 
    );

    return $self;
}

sub parse
{
    # Parse incoming $message, return
    # msgtype and "payload" as found within.
    my $self = shift;
    my $msg_to_parse = shift;
    my @payload;

    foreach my $msgtype (keys  %{$self->{parsers}})
    {
        # Try applying the parser to the incoming message
        $log->trace("checking for $msgtype");
        my @payload = $self->{parsers}{$msgtype}($msg_to_parse);
        

        # if $payload[0] is defined, then we know the parser have
        # found something so stop and return in the middle of the loop.
        if ($payload[0])
        {
            $log->trace("PARSER SAYS ITS A $msgtype i got this $payload[0]");
            return $msgtype, @payload;
        }
    }

    $log->debug("found nothing for $msg_to_parse ");

    return 0;

}

sub parse_response
{
    # Get the responses from the plugins,
    # and make sure that they follow rfc2812 grammar spec
    #
    #  ie:
    #  msg #test123123 bla bla bla bla
    #       becomes:
    #  PRIVMSG #test123123 :bla bla bla bla
    #
    #  and:
    #
    #  action #test123123 kramar gutta
    #       becomes:
    #  PRIVMSG #test123123 :ACTION  kramar gutta
    #
    my $self = shift;
    my @in_msgs = @_; # incoming messages from plugins
    my @out_msgs; # return this

    foreach my $msg (@in_msgs)
    {
       next unless $msg;
       $msg =~ s/^msg (\S+) /PRIVMSG $1 :/i;
       $msg =~ s/^me (\S+) /PRIVMSG $1 :\001ACTION /i;
       $msg =~ s/^action (\S+) /PRIVMSG $1 :\001ACTION /i;
       $msg .= "\r\n";
       push @out_msgs, $msg;
    }

    return @out_msgs;
}

sub parse_privmsg
{
    #parses the privmsg:s from the server and returns in a
    #format which gutta can understand.
    #
    #:doddo_!~doddo@localhost PRIVMSG #test123123 :doddo2000 (2)
    #:irc.the.net 250 gutta :Highest connection count: 3 (9 connections received)
    #
    my $self = shift;
    $_ = shift;
    
    m/^:(?<nick>[^!]++)!  # get the nick
         (?<mask>\S++)\s  # get the hostmask
               PRIVMSG\s  # this is how we know its a PRIVMSG
        (?<target>\S+)\s: # this is the target nick or chan
              (?<msg>.+)$ # rest of line would be msg /x;

    return $+{msg}, $+{nick}, $+{mask}, $+{target};
}

sub parse_353_nicks
{

    my $self = shift;
    $_ = shift;
    my @nicks;

    # RFC2812 https://tools.ietf.org/html/rfc2812
    #       353    RPL_NAMREPLY
    #              "( "=" / "*" / "@" ) <channel>
    #               :[ "@" / "+" ] <nick> *( " " [ "@" / "+" ] <nick> )
    #         - "@" is used for secret channels, "*" for private
    #           channels, and "=" for others (public channels).
    #

    m/^:(?<server>[^\s]++)\s  # get the server
                       353\s  # 353 is the nicks
      (?<own_nick>[^\s]++)\s  # own_nick
        (?<chantype>[=*@])\s  # What type of channel is this?
     (?<channel>\#[^\s]++)\s: # channel name
                (?<nicks>.+)$ # the nicks /x;


    # To avoid warning for splitting empty string
    # if the case is the msg is not a 353 NICKS msg.
    @nicks = split(' ', $+{nicks}) if $+{nicks};

    return $+{server}, $+{channel}, $+{chantype}, @nicks;
}

sub parse_366_end_of_names
{
    my $self = shift;
    $_ = shift;
    # Parse messages looking like this:
    # They tell that there are no more names/nicks joined to that chan,
    # so that the nicks returned from the 353:s are all there is in there.
    # :verne.freenode.net 366 gutta ##linux :End of /NAMES list.
    m/^:(?<server>[^\s]++)\s  # get the server
                       366\s  # "End of NAMES list."
      (?<own_nick>[^\s]++)\s  # own_nick
     (?<channel>\#[^\s]++)\s  # channel (don't care about restof msg) /x;

    return $+{server}, $+{channel};
}

sub parse_userquit
{
    my $self = shift;
    $_ = shift;
    # :felco!~felco@unaffiliated/felco QUIT :Read error: Connection reset by peer
    m/^:(?<nick>[^!]++)!  # get the nick
         (?<mask>\S++)\s  # get the hostmask
                  QUIT\s: # this is how we know hser did QUIT
              (?<msg>.+)$ # rest of line would be the QUITMSG /x;

    return $+{msg}, $+{nick}, $+{mask};

}

sub parse_joined_channel
{
    my $self = shift;
    $_ = shift;
    #:felco!~felco@unaffiliated/felco JOIN ##linux
    #:doddo!~doddo@192.168.60.187 JOIN :#test123123
      m/^:(?<nick>[^!]++)!  # get the nick
           (?<mask>\S++)\s  # get the hostmask
                    JOIN\s  # this is how we know hser did JOIN
                         :? # Sometimes the chan is prefix with a ":" colon ???
   (?<channel>\#[^\s]++)\s  # channel /x;

    return $+{nick}, $+{mask}, $+{channel};
}

sub parse_parted_channel
{
    my $self = shift;
    $_ = shift;
    # doddo!~doddo@192.168.60.187 PART #test123123
      m/^:(?<nick>[^!]++)!  # get the nick
           (?<mask>\S++)\s  # get the hostmask
                    PART\s  # this is how we know hser did JOIN
                         :? # Sometimes the chan is prefix with a ":" colon ???
   (?<channel>\#[^\s]++)\s  # channel /x;

    return $+{nick}, $+{mask}, $+{channel};
}



sub parse_470_forwarded_to_other_channel
{
    my $self = shift;
    
    # Looks like this:
    # :barjavel.freenode.net 470 gutta #linux ##linux :Forwarding to another channel
    # :gutta!~gutta@c80-216-80-238.bredband.comhem.se JOIN ##linux
    #
    #

}


1;
