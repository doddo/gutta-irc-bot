#!/usr/bin/perl
package Gutta::AbstractionLayer;
use strict;
use warnings;
use threads;
use Thread::Queue;
use Gutta::DBI;
use Data::Dumper;

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';

=head1 NAME

Gutta::Plugins::AbstractionLayer

=head1 SYNOPSIS

This is  the Gutta abstraction layer.


=head1 DESCRIPTION

This is to  the glue between the irc and the plugins

* to improve multitasking if some server is slow (by introducing threads and a message queue)
* a layer between the server connected entity and the plugins, to translate the plugins messages as appropriate for the server connected client using them, be it through irssi, any other IRC client, or standalone mode.
* a dispatcher.


=cut

# Getting the PLUGINS
my @PLUGINS = plugins();
my %PLUGINS = map { ref $_ => $_ } @PLUGINS;

# The plugins tasks queue
my $TASKQUEUE = Thread::Queue->new();
my $RESPONSES = Thread::Queue->new();

sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
               db => Gutta::DBI->instance(),
   parse_response => $params{parse_response},
         own_nick => $params{own_nick}||'gutta',
    workers2start => $params{workers2start}||4,
        cmdprefix => qr/^(gutta[,:.]\s+|[!])/,
    }, $class;

    # load commands and triggers from plugins
    $self->{triggers} = $self->_load_triggers();
    $self->{commands} = $self->_load_commands();

    # setting commandprefix based on own_nick
    if ($params{own_nick})
    {
        # TODO: this is ugly; fix.
        $self->{cmdprefix} = qr/(${params{own_nick}}[,:.]\s+|[!])/;
    }

    # Fire up the workers
    for (my $i=0; $i<=$self->{workers2start}; $i++)
    {
        # and save to a list
        push @{$self->{workers}}, threads->create({void => 1}, \&plugin_worker, $self, $i + 1)->detach();

    }

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
    # pass the heartbeat to the plugins.
    # heartbeats are things which gets called on a regular basis,
    # then it is up to each plugin to say what interval to act
    # then gets called the _heartbeat_act which typically does scheduled things
    my $self = shift;
    foreach my $plugin (@PLUGINS)
    {
        $plugin->heartbeat();
    }
}

sub heartbeat_res
{
    # Heartbeat res retrns result of the plugins and gets called per connected to
    # server.
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

sub plugin_res
{
    # The plugins are triggered by a variety of workers
    # these workers they put all the resulting IRC CMD:s in a big queue
    # This is the function where the caller (typically the client connected
    # to the IRC server) dequeues from this list.
    # Not dequeuing too much gives the possibility to avoid flooding etc.
    my $self = shift;
    my $max_responses = shift||4;
    # return x responses from the plugin workers to the main prog.

    return $RESPONSES->dequeue_nb($max_responses);

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

sub plugin_worker
{
    # The plugin workers will process all the incoming triggers/commands
    # This is to prevent a slow plugin fr example to block the whole bot
    # which is otherwise a big risk.
    my $self = shift;
    my $no = shift;

    print "*** Plugin Worker no#${no} is open and ready for business\n";

    while (my $inc_msg = $TASKQUEUE->dequeue())
    {
        my @responses;
        my ($tasktype, $plugin_ref, $command_or_trigger, $server, $msg, $nick, $mask,
           $target, $rest_of_msg) =  @{$inc_msg};
        print "worker #$no got a new msg of type $tasktype to process\n";
        if ($tasktype eq 'command')
        {
            push @responses, $PLUGINS{$plugin_ref}->command($command_or_trigger,$server,$msg,$nick,$mask,$target,$rest_of_msg);
        } elsif ($tasktype eq 'trigger'){
            push @responses, $PLUGINS{$plugin_ref}->trigger($command_or_trigger,$server,$msg,$nick,$mask,$target,$rest_of_msg);
        }

        @responses =  $self->_parse_response(@responses) if $self->{parse_response};

        # enqueue processed responses to the response queue
        foreach my $response (@responses)
        {
            $RESPONSES->enqueue($response);
        }

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

    # check first: is it a commandprefix - or a privmsg directly to bot?
    if (($msg =~ /${cmdprefix}/) or ($target eq $self->{own_nick}))
    {
        # get offset to be able to strip commandprefix from command.
        # Only used if the match is cmdprefix but still done here to keep close
        # to the regex (else there might be problems later)
        my $offset = length($&);
        my $command;
        my @rest_of_msg;

        if ($target eq $self->{own_nick})
        {
            ($command, @rest_of_msg) = split(/\s/,$msg);
            
            # OBS - if a privmsg to the BOT, then change target from bot->$nick.
            # because the sender of the message is logically the recipient of the
            # reply.
            $target = $nick;
        }
    
        if ($msg =~ /${cmdprefix}/)
        {
            # if match also the cmdprefix, then make sure to strip the command-
            # prefix from the message.
            ($command, @rest_of_msg) = split(/\s/,substr($msg,$offset));
        }
        
        # get all commands for all plugins.
        while (my ($plugin_ref, $commands) = each %{$self->{commands}})
        {
            # has plugin $plugin_ref a defined command which match?
            if (exists $$commands{$command})
            {

                warn "BINGO FOR $plugin_ref @ $command\n";
                # the msg with commandprefix stripped from it.
                my $rest_of_msg = join ' ', @rest_of_msg;

                # removing any crap from the msg.
                chomp($rest_of_msg);
                # OK now we know what to do, what plugin to do it with, and the
                # message to pass to the plugin etc. At this point it gets added 
                # to the queue.
                $TASKQUEUE->enqueue(['command', $plugin_ref, $command,$server,$msg,$nick,$mask,$target,$rest_of_msg]);
            }
        }
    }
    
    #
    # Process Triggers
    #

    # get all triggers for all plugins.
    while (my ($plugin_ref, $triggers) = each %{$self->{triggers}})
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
                # OK now we know what to do, what plugin to do it with, and the
                # message to pass to plugin etc. Add it to the queue of tasks to do
                $TASKQUEUE->enqueue(['trigger', $plugin_ref, $regex_trigger,$server,$msg,$nick,$mask,$target,$&]);
            }
        }
    }

    # TODO: past this point, no plugin no longer returns anything here,
    # BUT since some commands will at some point get parsed by other things than
    # plugins (for diagnosis, enabling/disabeling/reloading plugins etc)
    # this stub will still be here. 
    #

    # if running on standalone mode, then all these respnses needs to be
    # translated to the RFC 2812 syntax, so;
    #    if parse_response => 1 is sent to constructor fix the grammar.
    return $self->_parse_response(@responses) if $self->{parse_response};

    # else just return it as is.
    return @responses;

}
1;
