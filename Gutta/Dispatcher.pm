package Gutta::Dispatcher;
use strict;
use warnings;
use threads;
use Thread::Queue;
use Gutta::DBI;
use Gutta::Users;
use Gutta::Parser;
use Gutta::Session;
use Data::Dumper;
use Switch;
use Log::Log4perl;

# The logger
Log::Log4perl->init(Gutta::Constants::LOG4PERLCONF);
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Load the plugins.
use Module::Pluggable search_path => "Gutta::Plugins",
                          require => 1;


=head1 NAME

Gutta::Plugins::Dispatcher

=head1 SYNOPSIS

This is  the Gutta abstraction layer.


=head1 DESCRIPTION

This is to  the glue between the irc and the plugins

* Initialises the "gutta runtime environment
* Instansiates the plugins and put them in plugin worker threads.
* In theoury could put anything "in front of" the abstraction layer, so it is
easy to implement in other irc clients than gutta-standalone.pl
* a dispatcher.


=cut


# Getting the PLUGINS
my @PLUGINS;
my %PLUGINS;
my $PLUGINS;

# The plugins tasks queues
#
# This is the "default" task queue, for plugins which does not want a thread of 
# their own.
my $TASKQUEUE = Thread::Queue->new();
#
# This is the queue for storing HEARTBEATs when they are not inside of any of 
# the plugins TASKS queues.
my $HEARTBEAT = Thread::Queue->new();
#
# This is the output. The plugins generate value by refining the input. 
# Here's where this input is stored for sending through to the IRC server.
# It holds IRC commands sent from the plugins.
my $RESPONSES = Thread::Queue->new();

# The hash of Thread::Queue:s.
my %TASKS;


# The set of shared data
my $SESSION = Gutta::Session->instance();


sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
               db => Gutta::DBI->instance(),
           parser => Gutta::Parser->new(),
            users => Gutta::Users->new(),
   parse_response => $params{parse_response},
         own_nick => $params{own_nick}||'gutta',
          workers => [],
       heartbeats => [],
        cmdprefix => qr/^(gutta[,:.]\s+|[!])/,
    }, $class;

    # Initialise the gutta runtime environment:
    #

    # setting commandprefix based on own_nick
    if ($params{own_nick})
    {
        # TODO: this is ugly; fix.
        $self->{cmdprefix} = qr/(${params{own_nick}}[,:.]\s+|[!])/;
    }
    
    # initialise the plugins.
    $log->info("loading the plugins...");
    $self->__initialise_plugins();

    # initialise the threads.
    $log->info("starting the plugin threads...");
    $self->__initialise_threads();

    # start the workers
    $log->info("starting the plugin workers...");
    $self->__start_workers();

    return $self;
}


sub __initialise_plugins
{
    # Phase 1: loading the pluggins and getting some valuable nuggets of 
    # information from them.
    my $self = shift;

    # Instansiate the plugins
    @PLUGINS = map { $_->new() } plugins();
    %PLUGINS = map { ref $_ => $_ } @PLUGINS;
    $PLUGINS = \%PLUGINS;

    # load commands and triggers from plugins
    # This is all parsed from PRIVMSG:s
    $self->{triggers} = $self->_load_triggers();
    $self->{commands} = $self->_load_commands();

    # Plugins may also handle any event, using the event_handlers.
    $self->{event_handlers} = $self->_load_event_handlers();
}

sub __initialise_threads
{
    # Phase 2:Create an own Thread::Queue for the plugins which wants to run
    # in a thread of their own. This is to enable sorting out messages only for
    # them, and putting them into that Queue.
    #
    # This does not look very nice and TODO will be fixed in next release.
    my $self = shift;
    while (my ($plugin_ref, $plugin) = each %PLUGINS)
    {
        if ($plugin->{want_own_thread})
        {
            $TASKS{$plugin_ref} = Thread::Queue->new();
        } else {
            $TASKS{$plugin_ref} = $TASKQUEUE;
        }
    }
}



sub __start_workers
{
    # This sub fires up more workers and pushes them to the list of workers.
    # the $self->{workers} list.
    # if called with no arguments, start excactly one more worker.
    my $self = shift;
    my $workers2start = shift;
    my $i = 0;

    # First, handle the workers who wants their own threads.
    while (my ($plugin_ref, $plugin) = each %PLUGINS)
    {
        if ($PLUGINS{$plugin_ref}->{want_own_thread})
        {
            $log->debug("starting own thread for $plugin_ref with  $TASKS{$plugin_ref}");
            $self->start_worker(++$i,$TASKS{$plugin_ref});
        }
    }

    $log->debug("starting common thread");
    $log->debug($TASKQUEUE);
    # Start the "common" plugin worker.
    $self->start_worker($i+1, $TASKQUEUE);
}

sub _load_triggers
{
    # Get the triggers for the plugins and put them on a hash.
    # The triggers are regular expressions mapped to functions in the
    # plugins.
    my $self = shift;
    
    my %triggers;
    $log->info("GETTING TRIGGERS !!!");

    while (my ($plugin_key, $plugin) = each %PLUGINS)
    {
        next unless $plugin->can('_triggers');
        if (my $t = $plugin->_triggers())
        {
            $log->debug(sprintf "loaded %i triggers for %s\n", scalar keys %{$t}, $plugin_key);
            $triggers{$plugin_key} = $t;

            # Loading the context with these triggers now.
            $SESSION->set_plugincontext($plugin_key, 'triggers', keys %{$t});

        } else {
            $log->debug(sprintf "loaded 0 triggers for %s\n", $plugin_key);
        }
    }

    return \%triggers;
}

sub _load_commands
{
    # get the commands for the plugins and put them on a hash.
    # the commands are regular expressions mapped to functions in the
    # plugins.
    my $self = shift;
    
    my %commands;
    $log->info("getting commands !!!");

    while (my ($plugin_key, $plugin) = each %PLUGINS)
    {
        next unless $plugin->can('_commands');
        if (my $t = $plugin->_commands())
        {
            $log->debug(sprintf "loaded %i commands for %s", scalar keys %{$t}, $plugin_key);
            $commands{$plugin_key} = $t;
            # loading the context with these commands now.
            $SESSION->set_plugincontext($plugin_key, 'commands',  keys %{$t});
        } else {
            $log->debug(sprintf "loaded 0 commands for %s", $plugin_key);
        }
    }

    return \%commands;
}


sub _load_event_handlers
{
    # Read all plugins event handlers. Every MSG:type which the Gutta::Parser
    # can parse from the messages from the server it can by-pass to the event
    # handlers ...
    my $self = shift; 
    my %event_handlers;
    $log->info("getting event_handlers !!!");

    while (my ($plugin_key, $plugin) = each %PLUGINS)
    {
        next unless $plugin->can('_event_handlers');
        if (my $t = $plugin->_event_handlers())
        {
            $log->debug(sprintf "loaded %i event_handlers for %s", scalar keys %{$t}, $plugin_key);
            $event_handlers{$plugin_key} = $t;
            # loading the context with these event_handlers now.
            $SESSION->set_plugincontext($plugin_key, 'event_handlers',  keys %{$t});
        } else {
            $log->debug(sprintf "loaded 0 event_handlers for %s", $plugin_key);
        }
    }

    return \%event_handlers;
}



sub start_worker
{
    # This sub fires up one worker and pushes it to the list of workers.
    # the $self->{workers} list.
    # if called with no arguments, start excactly one more worker.
    my $self = shift;
    my $id = shift;
    my $queue = shift||$TASKQUEUE;

    $log->debug(sprintf "starting thread %i with queue %s", $id, $queue);

    # push this new worker and save to a list
    push @{$self->{workers}}, threads->create({void => 1}, \&plugin_worker, $self, $id, $queue)->detach();
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

sub plugin_worker
{
    # The plugin workers will process all the incoming triggers/commands
    # This is to prevent a slow plugin fr example to block the whole bot
    # which is otherwise a big risk.
    my $self = shift;
    my $no = shift;
    my $queue = shift;

    $log->info(sprintf "*** Plugin Worker no#%i is open and ready for business from %s", $no, $queue);

    while (my $inc_msg = $queue->dequeue())
    {
        my @responses;
        my ($timestamp, $tasktype, $plugin_ref, $eventtype, $server, @payload) = @{$inc_msg};

        $log->trace("worker #$no got a new msg of type $tasktype to process for $plugin_ref from queue $queue");
        if ($tasktype eq 'command')
        {
            my ($msg, $nick, $mask, $target, $rest_of_msg) = @payload;
            # check to see whether the plugin does exist.
            unless ($PLUGINS{$plugin_ref})
            {
                $log->warn("ignoring $tasktype for $plugin_ref; plugin is not there");
            } else {

                $log->debug(sprintf "thread #%-2i got command %s %s for queue %s", 
                                            $no, $eventtype, $plugin_ref, $queue);
                eval {
                    # Start the plugin "$plugin_ref";s  command. pass along all variables to it.
                    if ($PLUGINS{$plugin_ref} and $PLUGINS{$plugin_ref}->can('command'))
                    {
                        push @responses, $PLUGINS{$plugin_ref}->command($eventtype,
                                                    $server, $msg, $nick, $mask, $target, $rest_of_msg, $timestamp);
                    }
                };
                $log->error($@) if $@; # TODO fix.
            }
        } elsif ($tasktype eq 'trigger'){
            my ($msg, $nick, $mask, $target, $rest_of_msg) = @payload;
            $log->debug(sprintf "thread #%-2i got trigger %s %s for queue %s", 
                                            $no, $eventtype, $plugin_ref, $queue);
            eval {
                # Start the plugin "$plugin_ref";s triggers. pass along all variables to it.
                push @responses, $PLUGINS{$plugin_ref}->trigger($eventtype, 
                                            $server, $msg, $nick, $mask, $target, $rest_of_msg, $timestamp);
            };
            $log->error($@) if $@; # TODO fix.
        } elsif ($tasktype eq 'heartbeat') {
            # put a heartbeat into the plugin
            #
            # check to see whether the plugin does exist.
            unless ($PLUGINS{$plugin_ref})
            {
                $log->info("discarding heartbeat message for $plugin_ref; plugin is not there");
            } else {

                $log->trace(sprintf "thread #%-2i Got heartbeat for %-25s for queue %s", $no, $plugin_ref, $queue);
                eval {
                    if ($PLUGINS{$plugin_ref}->can('heartbeat'))
                    {
                        $PLUGINS{$plugin_ref}->heartbeat();
                        if ($PLUGINS{$plugin_ref}->can('heartbeat_res'))
                        {
                            push @responses, $PLUGINS{$plugin_ref}->heartbeat_res($server);
                            # OK the heartbeat have been run, so it can be put back into
                            # the queue
                        }
                    }
                };
                warn ($@) if $@; # TODO fix.
                $HEARTBEAT->enqueue($inc_msg);
            }

        } elsif ($tasktype eq 'event') {
            eval {
                if ($PLUGINS{$plugin_ref}->can('handle_event'))
                {
                    $PLUGINS{$plugin_ref}->handle_event($eventtype, $timestamp,  $server, @payload);
                }

            };
            warn ($@) if $@; # TODO fix            
 
        } elsif ($tasktype eq 'disable' or $tasktype eq 'reload')  {
            # Disable a plugin.
            $log->info("deleting ${plugin_ref} from worker ${no}.");
            delete $PLUGINS{$plugin_ref};
            my $i = 0;
            map { delete $PLUGINS[$i++] if ref $_ eq $plugin_ref } @PLUGINS;
        }
        
        # here we prepare the response standardised.
        @responses =  $self->{parser}->parse_response(@responses) if $self->{parse_response};

        # here we put responses into the responses queue.
        $RESPONSES->enqueue(@responses);
    }
    return $self;
}

sub init_heartbeat_queues
{
    # populates the heartbeats queue. by sending a heartbeat mesg to each plugin.
    # so then its up to each of the plugin workers to pass it on to the plugins
    # and its up to each plugin to decide how to act.
    #
    # Also this prevents a sloooow working plugin to recieve an overflow of heart
    # beats, because when heartbeat is processing, the message will remain in the
    # taskqueue for that plugin, and NOT in the heartbeat queue.
    # it's good design solution.
    my $self = shift;
    my $server = shift;
    
    # Define job for all the plugins.
    foreach my $plugin_ref (keys %PLUGINS)
    {
        if ($PLUGINS{$plugin_ref}->can('heartbeat'))
        {
            $log->debug("enqueing $plugin_ref for $server");
            # the message looks like this:
            $HEARTBEAT->enqueue([time, 'heartbeat', $plugin_ref, '', $server]);
        }
    }
}

sub heartbeat
{
    # This is the heartbeats. It moves tasks
    # from HEARTBEATS queue to the TASKQUEUE
    #
    # This one is expected to be called from a thread in the program using
    # Gutta::Abstractionlayer.
    my $self = shift;
    
    $log->trace("heartbeat thread is going to queue " . $HEARTBEAT->pending() . " pending tasks");
    foreach my $inc_msg ($HEARTBEAT->dequeue_nb(scalar @PLUGINS))
    {
        # make sure to sort message into correct queue by checking for
        # what plugin the message was intended. That is the 3:rd valie in the
        # array.
        my $plugin_ref = (@{$inc_msg})[2];
         
        # Grab all messages from HEARTBEAT queue. And put them back into the TASKQUEUE
        $log->trace(sprintf "passing heartbeat to %s in queue %s", $plugin_ref, $TASKS{$plugin_ref});
        $TASKS{$plugin_ref}->enqueue($inc_msg);
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

    $log->trace("ITS A $msgtype") if $msgtype;

    switch ($msgtype)
    {
             case 'PING' { push(@irc_cmds, "PONG $payload[0]\r\n") }
          case 'PRIVMSG' { @irc_cmds = $self->process_privmsg($server, @payload) }
        case /JOIN|PART/ { @irc_cmds = $self->process_join_or_part($server, $msgtype, @payload) }
              case '353' { @irc_cmds = $self->process_own_channel_join($server, @payload) }
             case 'QUIT' { @irc_cmds = $self->process_quit($server, @payload) }
    }

    if ($msgtype)
    {
        # Send the msg to appropriate plugins...
        $self->_send_to_plugins($msgtype, $server, @payload);
    }

    # if something returns IRC Commands, pass them through.
    return @irc_cmds;
}


sub _send_to_plugins
{
    # sends the message as parsed by the parser to the plugins who wants them.
    my $self = shift;
    my $msgtype = shift;
    my $server = shift;
    my @payload = @_;

    # get all  for all plugins.
    while (my ($plugin_ref, $event_handler) = each %{$self->{event_handlers}})
    {
        if (exists $$event_handler{$msgtype})
        {
            
            # if the message type incoming has any event handlers, then add the
            # message to those queues.
            $log->debug(sprintf 'sending event %s to plugin %s in queue %s', 
                                   $msgtype,  $plugin_ref, $TASKS{$plugin_ref});
            $TASKS{$plugin_ref}->enqueue([ time, 'event', $plugin_ref, $msgtype, $server, @payload]);
        }
    }
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

    # If someone on the irc says something, then that user will reveal its mask
    # That's something which the $SESSION want's to know.
    $SESSION->_set_nickinfo($nick, $mask, $target);



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

        # SPECIAL HANDLER FOR BOT ADMINISTRATIONS COMMAND.
        if ($command eq 'pluginctl')
        {
            # Managing the plugin needs to be handled outside of the plugins and directly
            # here, in the pluginctl functions.
            @responses = $self->_pluginctl($msg, $nick, $mask, $target, join ' ', @rest_of_msg);

        } else {
            
            # get all commands for all plugins.
            while (my ($plugin_ref, $commands) = each %{$self->{commands}})
            {
                # has plugin $plugin_ref a defined command which match?
                if (exists $$commands{$command})
                {
    
                    $log->debug("BINGO FOR $plugin_ref @ $command");
                    # the msg with commandprefix stripped from it.
                    my $rest_of_msg = join ' ', @rest_of_msg;
    
                    # removing any crap from the msg.
                    chomp($rest_of_msg);
                    # OK now we know what to do, what plugin to do it with, and the
                    # message to pass to the plugin etc. At this point it gets added
                    # to the queue.
                    $log->debug(sprintf 'enqueuing command %s for %s in queue %s', 
                                                     $command,  $plugin_ref, $TASKS{$plugin_ref});
                    $TASKS{$plugin_ref}->enqueue([ time, 'command', $plugin_ref, $command, $server, 
                                                          $msg, $nick, $mask, $target, $rest_of_msg ]);
                }
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
                $log->debug(printf 'trigger "%s" matched "%s" for plugin %s.', $regex_trigger, $&, $plugin_ref);
                # OK now we know what to do, what plugin to do it with, and the
                # message to pass to plugin etc. Add it to the queue of tasks to do
                $TASKS{$plugin_ref}->enqueue([ time, 'trigger', $plugin_ref, $regex_trigger, $server, 
                                                      $msg, $nick, $mask, $target, $&  ]);
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

sub process_join_or_part
{
    my $self = shift;
    my $server = shift;
    my $what = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    $log->debug("I just found out that $nick $what:ed $channel on $server.");

    if ($what eq 'JOIN')
    {
        $SESSION->_process_join($nick,$mask,$channel);
    } elsif ($what eq 'PART') {
        $SESSION->_process_part($nick,$mask,$channel);
    }

    return;
}

sub process_quit
{
    my $self = shift;
    my $server = shift;
    my $nick = shift;
    my $mask = shift;

    $log->debug("I just found out that $nick whith hostmask $mask QUIT:ed");

    $SESSION->_process_quit($nick, $mask);

    return;
}

sub process_own_channel_join
{
    # Process the incoming 353 msg from the parser. This is when the bot joins some channel.
    # it returns 
    #
    #    $+{server}, $+{channel}, $+{chantype}, @nicks;
    #
    # But the dispatcher adds the $server, but that we dont care about for now
    my $self = shift;
    my $server = shift; # This is the server connected to from the bot
    my $ircserver = shift; # This is how that server names itself .
    my $channel = shift;
    my $chantype = shift; # <-- This is discarded for now -..
    my @nicks = @_;

    $log->debug("processing 353 for $channel, server=$server,type=$chantype");

    # Add the populate the session with this data!!!
    $SESSION->_set_nicks_for_channel($server, $channel, @nicks);

    return;

}


sub quit
{
    my $self = shift;

}


sub quit_irc
{
    my $self = shift;
    # return the client QUIT msg to the server, which then disconnects you...
    # 

    # A quit message optional
    my $quitmsg = shift || "https://github.com/doddo/gutta-irc-bot";
    my $quitcmd = "QUIT :$quitmsg\r\n";

    # here we put quitmsg into the responses queue.
    $RESPONSES->enqueue($quitcmd);

    # Here we clean up the session-db file.
    # guttacleanup;

    return;

}

sub _pluginctl
{
    # THis is a very 
    my $self = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    my @responses;

    $log->info("Got Admincmd from ${nick}. hen vill $rest_of_msg");
    # Check if user is logged in and is admin (Gutta::Users)
    unless ($self->{ users }->is_admin_with_session($nick))
    {
       return "msg $target $nick operation not permitted.";
    }

    # Check if there's the $rest_of_msg 
    unless ($rest_of_msg)
    {
        return "msg $target $nick need subcmd (help not implemented yet)";
    }


    my ($subcmd, @opts ) = split(' ', $rest_of_msg);
    
    switch($subcmd)
    {
        case    'list'  { @responses = map {"msg ${target} ${nick}: " . $_ } keys %PLUGINS}
        case 'disable'  { push(@responses, "msg $target $nick Want to disable a plugin?") }
        case 'enable'   {}
        case 'reload'   {}
    }
    # parse rest of msgs:




    return @responses;
}
1;
