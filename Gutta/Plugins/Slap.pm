package Gutta::Plugins::Slap;
# can slap with this one

use parent Gutta::Plugin;

sub process_msg
{
    my $self = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;

    if ($msg =~ m/^!slap\s+(\S+)/)
    { 
       return "action $target slaps $1 around a bit with a large trout.";
    } else { 
       return ();
    }
}
1;
