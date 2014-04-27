#!/usr/bin/perl
package Gutta::Context;
use strict;
use warnings;
use Data::Dumper;

=head1 NAME

Gutta::Context

=head1 SYNOPSIS

Using the Gutta::Parser etc, the Gutta::Context keeps track of everything the bot knows from the IRC server.

=head1 DESCRIPTION

Gutta::Context contains real-time information about everything gutta the IRC bot knows. This includes but is not
limited to  what channels the bot have joined, what nicks are in that channel. If the server have said anything "of value" about a nick
then the Gutta::Context shall keep track of this for Gutta aswell.

This information gets fed into the Plugins somehow, so if they need to know what nicks have joined a channel or something, then this Gutta::Context
will keep track of this for them.

I think Gutta::Abstractionlayer needs to actively feed this information into the plugins since they use threads and NEED the latest info. If they don't
get it from the database instead, TBD.

THIS IS YET A STUB.


=cut

sub new
{
    my $class = shift;
    my %params = @_;
    my $self = bless {
    }, $class;

    return $self;
}

sub update_context
{
    my $self = shift;
    #trigger this under some circumstances,
    # it may be certain messages from the IRC server, like JOIN, PART
    # QUITS and so forth.
    # Keep this stored somewhere.
    

    

}

