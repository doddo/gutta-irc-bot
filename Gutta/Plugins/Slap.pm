package Gutta::Plugins::Slap;
# can slap with this one

use parent 'Gutta::Plugin';

sub slap
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
    # they need someonw to slap
    return unless $rest_of_msg;

    return "msg $target \001ACTION  slaps $rest_of_msg  around a bit with a large trout.";
}


sub _commands
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    return {

        "slap" => sub { $self->slap(@_) },

    }
}
1;
