package Gutta::Plugins::Meta;
# can meta with this one

use Pod::Usage;
use Data::Dumper;
use parent Gutta::Plugin;

sub help
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
    # they need someonw to meta
    return unless $rest_of_msg;
    
    my $helpmsg;

    # I have to fool pod2usage into thinking that 'HELPMSG_FILEHANDLE'
    # is actually a file but it is a variable: "$helpmsg".
    open( HELPVAR, '>', \$helpmsg);
   
    my $filehandle = \*HELPVAR;

    print $filehandle "OK OK";

    pod2usage( -verbose => 99,
              -sections =>  [ qw(unmonitor/hostgroup) ],
                 -input => 'Gutta/Plugins/Nagios.pm',
                -output => $filehandle,
               -exitval => 'NOEXIT');

    close (HELPVAR), # Close this file handle.

    print Dumper($helpmsg);


#    return "msg $target \001ACTION  metas $rest_of_msg  around a bit with a large trout.";
}


sub _commands
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    return {

        "help" => sub { $self->help(@_) },

    }
}
1;
