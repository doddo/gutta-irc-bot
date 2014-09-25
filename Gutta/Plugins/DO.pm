package Gutta::Plugins::DO;
# Allows admins to make bot run irc commands
#
use Gutta::Users;
use parent 'Gutta::Plugin';

use strict;
use warnings;
use Data::Dumper;

=head1 NAME

Gutta::Plugins::DO

=head1 SYNOPSIS

Facilities to make bot DO things.

=head1 DESCRIPTION

Tell bot what to DO and it will try to execute.

=head1 DO

Bot can DO things: Whatever printed after the DO keyword will be parsed and done on the server from which the command executed.

For example:

!DO JOIN #Linux

And gutta irc bot will join #Linux, (or try atleast).

=cut

my $log = Log::Log4perl->get_logger(__PACKAGE__);


sub _initialise
{
    # initialising the DO module
    my $self = shift;
    $self->{users} = Gutta::Users->new();
}

sub do
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
    return unless $rest_of_msg;

    return "msg $target please identify first." unless $self->{users}->has_session($nick, $mask); 
    #  b) is an admin henself.
    my $nick_reginfo = $self->{users}->get_user($nick);
    
    return "msg $target NO." unless $$nick_reginfo{'admin'};

    return ("msg $target OK $nick, -  I will try.", $rest_of_msg);
}


sub _commands
{
    my $self = shift;
    # override this in plugin to set custom commands
    #
    return {

        "DO" => sub { $self->do(@_) },

    }
}
1;
