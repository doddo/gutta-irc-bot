#!/usr/bin/perl
package Gutta::Session::Nick;
use strict;
use warnings;
use Data::Dumper;
use Gutta::DBI;
use Gutta::Parser;
use Gutta::Constants;
use Log::Log4perl;

=head1 NAME

Gutta::Session::Nick

=head1 SYNOPSIS

The Gutta::Session::Nick 

=head1 DESCRIPTION

TODO: write something here...


=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub new
{
    my $class = shift;
    my %params = @_;
    
    my $self  = bless {
        nick => $params{ nick } || undef,
        mask => $params{ mask } || undef,
    }, $class;

    return $self;
}

sub nick
{
    # nick setter and getter
    my $self = shift;

    my $nick = shift || return $self->{ nick };

    $self->{ nick } = $nick

}

sub mask
{
    # mask setter and getter
    my $self = shift;

    my $mask = shift || return $self->{ mask };

    $self->{ mask } = $mask

}

sub join_channel
{
    my $self = shift;
    #TODO

}

sub part_channel
{
    my $self = shift;
    #TODO
}

sub channels
{
    my $self = shift;
    #TODO
}

1;
