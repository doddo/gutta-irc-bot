package Gutta::Plugins::Slap;
# can slap with this one

use parent Gutta::Plugin;

sub process_msg
{
    my $self = shift;
    my $msg = shift;
    

    if ($msg =~ m/^!slap\s+(\S+)/)
    { 
       return "$1 got slapped around a bit with a large trout.";
    } else { 
       return ();
    }
}
1;
