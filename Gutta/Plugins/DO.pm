package Gutta::Plugins::DO;
# Allows admins to make bot run irc commands
#
use Gutta::Users;

use parent Gutta::Plugin;

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
