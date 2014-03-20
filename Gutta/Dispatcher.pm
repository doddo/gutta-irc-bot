#!/usr/bin/perl
package Gutta::Dispatcher;
use strict;
use warnings;
use threads;
use Gutta::DBI;
use Data::Dumper;

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';


my @PLUGINS = plugins();
my %PLUGINS = map { ref $_ => $_ } @PLUGINS;


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

    return $self;

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

