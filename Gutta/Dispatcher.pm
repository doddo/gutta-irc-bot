#!/usr/bin/perl
package Gutta::Dispatcher;
use strict;
use warnings;
use threads;
#use Thred::Queue;
use Gutta::DBI;
use Data::Dumper;

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';


my @PLUGINS = plugins();
my %PLUGINS = map { ref $_ => $_ } @PLUGINS;

#my $cmdq = Thread::Queue->new();


print join "\n", keys %PLUGINS;

# This is  the Gutta abstraction layer.
# #
#
#  This will be the glue between the irc and the plugins
#
#  to improve multitasking if osme server is slow
#

$|++;

sub new 
{
    my $class = shift;

    my $self = bless {
               db => Gutta::DBI->instance(),
    primary_table => 'users'
    }, $class;

    $self->{triggers} = $self->_get_triggers();
    $self->{commands} = $self->_get_commands();

    return $self;
}


sub _get_triggers
{
    # Get the triggers for the plugins and put them on a hash.
    # The triggers are regular expressions mapped to functions in the 
    # plugins.
    my $self = shift;
    
    my %triggers; 

    foreach my $plugin_key (keys %PLUGINS)
    {
        next unless $PLUGINS{$plugin_key}->can('get_triggers');
        $triggers{$plugin_key} = $PLUGINS{$plugin_key}->get_triggers();
    }

    return \%triggers;
}

sub _get_commands
{
    # Get the commands for the plugins and put them on a hash.
    # The commands are the first part of a message and has a custom
    # prefix or something.
    # 
    my $self = shift;
    
    my %commands; 

    foreach my $plugin_key (keys %PLUGINS)
    {
        next unless $PLUGINS{$plugin_key}->can('get_commands');
        $commands{$plugin_key} = $PLUGINS{$plugin_key}->get_commands();
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


1;

