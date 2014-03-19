#!/usr/bin/perl
package Gutta::Dispatcher;
use strict;
use warnings;
use threads;
use Gutta::DBI;

# This is a dispatcher STUB
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

sub dispatch
{
    my $self = shift;
    my @fwords = qw/& ! @ $ ^ R 5 ¡ £ +/;     
    my %thr;

    while (my $char = shift(@fwords))
    {
        print "starting thread $char.\n";
        $thr{$char} = threads->create({void => 1}, \&gutta_worker, $char);
    }

}

sub gutta_worker
{

    my $char = shift;
    my $nextsleep = 1;

    while (sleep $nextsleep)
    {
        $nextsleep = int(rand(2)) + 1;
        print $char;
        
    }
}

1;
