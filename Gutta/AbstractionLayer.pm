#!/usr/bin/perl
package Gutta::AbstractionLayer;
use strict;
use warnings;
use threads;
use Thread::Queue;
use Gutta::DBI;
use Gutta::Parser;
use Data::Dumper;
use Switch;

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

# The plugins tasks queues
my $TASKQUEUE = Thread::Queue->new();
my $HEARTBEAT = Thread::Queue->new();
my $RESPONSES = Thread::Queue->new();


sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
               db => Gutta::DBI->instance(),
           parser => Gutta::Parser->new(),
   parse_response => $params{parse_response},
         own_nick => $params{own_nick}||'gutta',
    workers2start => $params{workers2start}||4,
          workers => [],
       heartbeats => [],
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
    $self->start_workers($self->{workers2start});

    return $self;
}

sub start_workers
{
    # This sub fires up more workers and pushes them to the list of workers.
    # the $self->{workers} list.
    # if called with no arguments, start excactly one more worker.
    my $self = shift;
    my $workers2start = shift||1;

    # Start more workers.
    for (my $i = scalar @{$self->{workers}}||0; $i<=$workers2start; $i++)
    {
        # and save to a list
        push @{$self->{workers}}, threads->create({void => 1}, \&plugin_worker, $self, $i + 1)->detach();

    }
}

sub start_heartbeat
{
    # This jobs starts the heartbeats for $server
    # and it will pass this along ping pong to the workers.
    my $self = shift;
    my $server = shift;
    
    # must pass $server to threads.
    unless ($server)
    {
        warn "missing heartbeat args...\n"; 
        return;
    }

    # initialise heartbeat therad if not started already.
    if ($server ~~ @{$self->{heartbeats}})
    {
        warn "heartbeats for thet server $server started already.. Next version maybe will be able to restart it\n";
    } else {
        # Define job for all the plugins.
        foreach my $plugin_ref (keys %PLUGINS)
        {
            print "enwueing $plugin_ref for $server \n";
            $HEARTBEAT->enqueue(['heartbeat', $plugin_ref, '', $server]);
        }
        # and save to a list
        push @{$self->{heartbeats}}, threads->create({void => 1}, \&heartbeats)->detach();
    }
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

sub heartbeats
{
    # This is the heartbeats. It moves tasks
    # from HEARTBEATS queue to the TASKQUEUE
    #
    my $self = shift;
    warn "starting heartneats\n";
    
    while (sleep 3)
    {
            warn "HELLO " . $HEARTBEAT->pending() . " \n";
        foreach my $inc_msg ($HEARTBEAT->dequeue_nb(scalar @PLUGINS))
        {
            # Grab all messages from HEARTBEAT queue.
            # And put them back into the TASKQUEUE
            warn "enqueueing something from the plugins\n";
            $TASKQUEUE->enqueue($inc_msg);
        }
    }
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
        print "worker #$no got a new msg of type $tasktype to process for $plugin_ref\n";
        if ($tasktype eq 'command')
        {
            # Start the plugin "$plugin_ref";s  command. pass along all variables to it.
            push @responses, $PLUGINS{$plugin_ref}->command($command_or_trigger,$server,$msg,$nick,$mask,$target,$rest_of_msg);
            # Start the plugin "$plugin_ref";s triggers. pass along all variables to it.
        } elsif ($tasktype eq 'trigger'){
            push @responses, $PLUGINS{$plugin_ref}->trigger($command_or_trigger,$server,$msg,$nick,$mask,$target,$rest_of_msg);
        } elsif ($tasktype eq 'heartbeat') {
            # put a heartbeat into the plugin
            #
            $PLUGINS{$plugin_ref}->heartbeat();
            push @responses, $PLUGINS{$plugin_ref}->heartbeat_res($server);
            # OK the heartbeat have been run, so it can be put back into
            # the queue
            $HEARTBEAT->enqueue($inc_msg);
        }
        
        # here we prepare the response standardised.
        @responses =  $self->{parser}->parse_response(@responses) if $self->{parse_response};

        # enqueue processed responses to the response queue
        foreach my $response (@responses)
        {
            $RESPONSES->enqueue($response);
        }
    }
}


sub process_msg
{
    # The PROCESS MSG takes a look at all incoming IRC messages (almost), and
    # based on what is sent to it, acts accordingly,
    #
    # Typically the responses gets pushed to a queue by one of the workers, but
    # the possibility exists for GAL to handle messages directly, so this sub
    # therefore returns a list of @irc_cmds, even if its typically empty most
    # of the times.
    #
    my $self = shift;
    my $server = shift;
    my $message = shift;
    my @irc_cmds;
    
    # ask the parser to parse the incoming $message from the server.
    my ($msgtype, @payload) = $self->{parser}->parse($message);

    print "ITS A $msgtype\n" if $msgtype;

    switch ($msgtype)
    {
        case 'PRIVMSG' { @irc_cmds = $self->process_privmsg($server, @payload) }

    }

    return @irc_cmds;
}

sub process_privmsg
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
    return $self->{parser}->parse_response(@responses) if $self->{parse_response};

    # else just return it as is.
    return @responses;

}
1;
