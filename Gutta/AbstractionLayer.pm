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
* to enable gutta to hook into any irc client (not only Irssi)
* to enable standalone mode (in the future)


=cut

# Getting the PLUGINS 
my @PLUGINS = plugins();
my %PLUGINS = map { ref $_ => $_ } @PLUGINS;

#my $cmdq = Thread::Queue->new();

# print join "\n", keys %PLUGINS;


$|++;

sub new 
{
    my $class = shift;

    my $self = bless {
               db => Gutta::DBI->instance(),
    primary_table => 'users'
    }, $class;

    $self->{triggers} = $self->_load_triggers();
    $self->{commands} = $self->_load_commands();

    return $self;
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
    my $cmdprefix = qr/gutta[,:]/; #TODO FIX    
    my @responses; # return this.

    # 
    # Process Commands
    #

    # check first: is it a commandprefix?, then: match potential_command with
    # all the plugins commands.
    my ($potential_cmdprefix, $command) = (split(/\s/, $msg))[0,1];    
    print "PROCESSING MESSAGE $msg\n";

    if ($potential_cmdprefix =~ /${cmdprefix}/)
    {
        # get all commands for all plugins.
        while (my ($plugin_ref, $commands) = each $self->get_commands())
        {
            # has plugin $plugin_ref a defined command which match?
            if (exists $$commands{$command})
            {
                warn "BINGO FOR $plugin_ref @ $command\n";
                # TODO: THIS COULD BE STARTED IN A THREAD AND/OR INSERTED INTO THE DB:
                push @responses, $PLUGINS{$plugin_ref}->command($command,$server,$msg,$nick,$mask,$target);
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
    warn "FOUND NOTHING\n";
    warn "server:$server,msg:$msg,nick:$nick,mask:$mask,targtt:$target\n";
    return @responses;
}
1;
