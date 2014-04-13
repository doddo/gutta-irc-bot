#!/usr/bin/perl
package Gutta::Parser;
use strict;
use warnings;
use Data::Dumper;

=head1 NAME

Gutta::Parser

=head1 SYNOPSIS

Parse and format messages to and from IRC server and Gutta::Plugins.

=head1 DESCRIPTION

The Gutta::Parser parses incoming messages from the irc server, and speaks with the dispatcher who fires up the plugins, and the response from the Dispatcher passes the Parser too, and gets translated to a format suitable for the irc server

=cut

sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
    }, $class;

    return $self;
}

sub set_cmdprefix
{
    # The cmdprefix is the prefix for the commands.
    # command "slap" gets prefixed by this.
    my $self = shift;
    my $cmdprefix = shift;
    $self->{cmdprefix} = $cmdprefix;
}

sub get_cmdprefix
{
    # The cmdprefix is the prefix for the commands.
    # this function returns the cmdprefix.
    my $self = shift;
    return $self->{cmdprefix};
}

sub parse
{
    # Parse incoming $message, return
    # msgtype and "payload" as found within.
    my $self = shift;
    my $message = shift;

    if ($message =~ m/^:[^:]+ PRIVMSG/)
    {
        return 'PRIVMSG', $self->parse_privmsg($message);

    }
    

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

1;
