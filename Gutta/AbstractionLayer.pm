#!/usr/bin/perl
package Gutta::AbstractionLayer;
use strict;
use warnings;
use threads;
#use Thred::Queue;
use Gutta::DBI;
use Data::Dumper;

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';

=head1 NAME

Gutta::Plugins::AbstractionLayer

=head1 SYNOPSIS

This is  the Gutta abstraction layer.


=head1 DESCRIPTION

This is to  be the glue between the irc and the plugins

* to improve multitasking if some server is slow (by introducing threads and a message queue)
* to enable gutta to hook into "any" IRC client (not only Irssi)
* to enable standalone mode


=cut

# Getting the PLUGINS 
my @PLUGINS = plugins();
my %PLUGINS = map { ref $_ => $_ } @PLUGINS;

#my $heartbeat_mq = Thread::Queue->new();

# print join "\n", keys %PLUGINS;


$|++;

sub new 
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
               db => Gutta::DBI->instance(),
    primary_table => 'users',
   parse_response => $params{parse_response},
        cmdprefix => qr/^(gutta[,:]|[!])/,
    }, $class;

    $self->{triggers} = $self->_load_triggers();
    $self->{commands} = $self->_load_commands();

    return $self;
}

sub set_cmdprefix
{
    # The cmdprefix is the prefix for the commands.
    # command "slap" gets prefixed by this.
    my $self = shift;
    my $cmdprefix = shift;
    $self->{cmdprefix} = qr/^$cmdprefix/;
}

sub get_cmdprefix
{
    # The cmdprefix is the prefix for the commands.
    # this function returns the cmdprefix.
    my $self = shift;
    return $self->{cmdprefix};
}

sub get_triggers
{
    my $self = shift;
    return $self->{triggers};
}

sub get_commands
{
    my $self = shift;
    return $self->{commands};
}

sub _load_triggers
{
    # Get the triggers for the plugins and put them on a hash.
    # The triggers are regular expressions mapped to functions in the 
    # plugins.
    my $self = shift;
    
    my %triggers; 
    warn "GETTING TRIGGERS !!!\n";

    while (my ($plugin_key, $plugin) = each %PLUGINS)
    {
        next unless $plugin->can('_triggers');
        if (my $t = $plugin->_triggers())
        {    
            warn sprintf "loaded %i triggers for %s\n", scalar keys %{$t}, $plugin_key;
            $triggers{$plugin_key} = $t
        } else {
            warn sprintf "loaded 0 commands for %s\n", $plugin_key;
        }
    }

    return \%triggers;
}

sub heartbeat
{
    my $self = shift;
    foreach my $plugin (@PLUGINS)
    {
        $plugin->heartbeat();
    }
}

sub heartbeat_res
{
    my $self = shift;
    my $server = shift;
    my @responses;

    foreach my $plugin (@PLUGINS)
    {
        push @responses, $plugin->heartbeat_res();
    }

    # if running on standalone mode, then all these respnses needs to be 
    # translated to the RFC 2812 syntax, so;
    #    if parse_response => 1 is sent to constructor fix the grammar.
    return $self->_parse_response(@responses) if $self->{parse_response};

    # else just return it as is.
    return @responses;


}

sub _parse_response
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




sub _load_commands
{
    # Get the commands for the plugins and put them on a hash.
    # The commands are regular expressions mapped to functions in the 
    # plugins.
    my $self = shift;
    
    my %commands; 
    warn "GETTING COMMANDS !!!\n";

    while (my ($plugin_key, $plugin) = each %PLUGINS)
    {
        next unless $plugin->can('_commands');
        if (my $t = $plugin->_commands())
        {    
            warn sprintf "loaded %i commands for %s\n", scalar keys %{$t}, $plugin_key;
            $commands{$plugin_key} = $t;
        } else {
            warn sprintf "loaded 0 commands for %s\n", $plugin_key;
        }
    }

    return \%commands;
}

sub start_workers
{
    my $self = shift;
    my @fwords = qw/& ! @ $ ^ R 5 ¡ £ +/;     
    my %thr;

    #while (my $char = shift(@fwords))
    foreach (keys %PLUGINS)
    {
        print "starting thread $_";
        $thr{$_} = threads->create({void => 1}, \&gutta_worker, $self, $_);
    }
}

sub gutta_worker
{
    my $self = shift;
    my $char = shift;

    print "starting thread $char . \n";
    my $nextsleep = 1;

    while (sleep int(rand(2)) + 1)
    {
        print $char;
    }
}

sub process_msg
{
    #
    #  process incoming message $msg (rest is "context" ;)
    #  return an array of responses from the plugins
    #  the responses are pure IRC commands.
    #  
    #  Several plugins may respond (diffrently) to the same
    #  message. 
    #
    my $self = shift;
    my $server = shift; # the IRC server
    my $msg = shift;    # The message
    my $nick = shift;   # who sent it?
    my $mask = shift;   # the hostmask of who sent it
    my $target = shift||$nick; # for privmsgs, the target (a channel)
                               # will be the nick instead. makes sense
                               # bcz privmsgs have no #channel, but should
                               # get the response instead,
    my $cmdprefix = $self->{cmdprefix};

    my @responses; # return this.

    # 
    # Process Commands
    #

    # check first: is it a commandprefix?
    if ($msg =~ /${cmdprefix}/)
    {
        # then , then: match potential_command with all the plugins commands.
        my ($command, @rest_of_msg) = split(/\s/,substr($msg,(@+ - 1)));
        
        # get all commands for all plugins.
        while (my ($plugin_ref, $commands) = each $self->get_commands())
        {
            # has plugin $plugin_ref a defined command which match?
            if (exists $$commands{$command})
            {

                warn "BINGO FOR $plugin_ref @ $command\n";
                # the msg with commandprefix stripped from it.
                my $rest_of_msg = join ' ', @rest_of_msg;
            
                # TODO: THIS COULD BE STARTED IN A THREAD AND/OR INSERTED INTO THE DB:
                push @responses, $PLUGINS{$plugin_ref}->command($command,$server,$msg,$nick,$mask,$target,$rest_of_msg);
            } 
        }
    }
    
    # 
    # Process Triggers
    #

    # get all triggers for all plugins.
    while (my ($plugin_ref, $triggers) = each $self->get_triggers)
    {
        # traverse through all configured triggers (they are regular expressions)
        # and match against incoming message $msg. Any matches - they can be run in
        # plugin containing that trigger.
        foreach my $regex_trigger (keys %{$triggers})
        {
            if ($msg  =~ /$regex_trigger/)
            {
                # Here a regex matched. That was from $plugin_ref.
                warn sprintf 'trigger "%s" matched "%s" for plugin %s.', $regex_trigger, $&, $plugin_ref;
                
                # TODO: THIS COULD BE STARTED IN A THREAD AND/OR INSERTED INTO THE DB:
                push @responses, $PLUGINS{$plugin_ref}->trigger($regex_trigger,$server,$msg,$nick,$mask,$target, $&);
            }
        } 
    }

    # if running on standalone mode, then all these respnses needs to be 
    # translated to the RFC 2812 syntax, so;
    #    if parse_response => 1 is sent to constructor fix the grammar.
    return $self->_parse_response(@responses) if $self->{parse_response};

    # else just return it as is.
    return @responses;

}
1;
