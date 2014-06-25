package Gutta::Plugins::CTCP;

=head1 NAME

Gutta::Plugins::CTCP

=head1 SYNOPSIS

Handles some of the most common CTCP replies.

=head1 DESCRIPTION

Handles replies for CTCP messages like PING, VERSION etc.

=cut


use parent Gutta::Plugin;
use Gutta::Constants;
use strict;
use warnings;
use Switch;
use POSIX;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub handler
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $match = shift;

    my $command;
    my $reply;
    
    if ($target !~ /^#/)
    {

        if ($msg =~ m/^\001([A-Z]+) ?/)
        {
            $command = $1;
            $log->debug("in comes a $command");

        };

        switch ($command)
        {
            case 'PING'    { $reply = time }
            case 'VERSION' { $reply = "Gutta-IRC-bot " . Gutta::Constants::VERSION . " on " . "$^O" }
            case 'TIME'    { $reply = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime) }
        }; 
        if (!$reply)
        {
            $reply = "Unrecognized CTCP command";
        }
        # What to reply to the sender
        my $response = "NOTICE $nick :\001$command: $reply\001";
     
        $log->debug("will reply with this $response");

        return $response;
    }

    return;
}


sub _triggers
{
    my $self = shift;
    #
    # A CTCP message is implemented as a PRIVMSG or NOTICE 
    # where the first and last characters of the message are ASCII value 0x01. 
    return {

        qr/^\001/ => sub { $self->handler(@_) },

    }
}
1;
