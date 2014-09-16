package Gutta::Session;
use warnings;
use strict;
use vars qw(@ISA);
our @ISA = qw(Class::Singleton);

use Data::Dumper;

use threads;
use threads::shared;

use Scalar::Util;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

Gutta::Session

=head1 SYNOPSIS

Holds info which is shared between classes etc. This gonan replace Gutta::Context


=head1 DESCRIPTION

Most of the things known by gutta will be stored here for later use.

=cut


sub _new_instance
{
    # The constructor.
    # Here we share some different hashes for use in data representation.
    #
    #
    my $class = shift;
    share(my %self);
    
    my %n;
    my %c;
    my %p;
   
    $self{ nicks } = shared_clone(\%n);
    $self{ channels} = shared_clone(\%c);
    $self{ plugincontext } = shared_clone(\%p);
    
    return (bless(\%self, $class));
}

sub set_plugincontext
{
    # Sets the plugins commands and triggers, and saves them.

    my $self = shift;
    my $plugin_ref = shift;
    my $what_it_is = shift;
    my @payload = @_;

    $log->debug("Setting context keys for $plugin_ref -> $what_it_is");

    my $pc = \%{$self->{ plugincontext }};
    
    unless (exists  $pc->{ $what_it_is })
    {
        my %p: shared;
        $$pc{$what_it_is} = \%p;
    }


    foreach (@payload)
    {

        $self->{ plugincontext }->{$what_it_is}->{$_} = $plugin_ref;
    }
}

sub get_plugin_commands
{
    # Return a list of al the commands registered from the plugins
    my $self = shift;

    return $self->{ plugincontext }->{ 'commands' };
}

sub _join_nick_to_channel
{
    #  Associates a nick with a channel.
    #   puts as much info as possible into that nick 
    #   update étc.

    my $self = shift;
    my $nick = shift;
    my $channel = shift;

    my $nick_data = shift; #<-- this is hash_ref...

    lock($self);
    my $vars = \%{$self->{channels}};

    unless (exists $$vars{$channel})
    {
        my %p: shared;
        $$vars{$channel} = \%p;
        $log->info("initialising $channel...");
    }

    unless (exists $$vars{$channel}{$nick})
    {
        my %p: shared;
        $$vars{$channel}{$nick} = \%p;
    }
    
    my $nick_ref = \%{$self->{ channels }{$channel}{$nick}};

    # Copying the found data over => the nickinfo for found channel.
    while ( my ($key, $value) = each(%$nick_data) ) {
        $log->trace( "$key => $value");
        $$nick_ref{$key} = $value;
    }

    $log->trace(Dumper($self->{ channels }{$channel}));
}


sub _set_nicks_for_channel
{
    # when recieving a 353 NICKS from the Gutta::Dispatcher, process it here
    # and process the data ...
    my $self = shift;
    my $server = shift;
    my $channel = shift;
    my @nicks = @_;
    my %nicklist;

    $log->debug("Processing a 353");

    foreach my $nick (@nicks)
    {
        my $op = 0;
        my $voice = 0;
        my $mode;
        # Check if nick is an operator or has voice
        if ($nick =~ s/^([+@])//)
        {
           $mode = $1; 
        }
        $log->info("'$nick' is joined to '$channel'...");

        my %n = (
              nick => $nick,
              mode => $mode,
        );

        $self->_join_nick_to_channel($nick, $channel, \%n);
    }
}

sub get_nicks_from_channel
{
    my $self = shift;
    my $channel = shift;
    
    unless (exists $self->{ channels }{$channel})
    {
        $log->warn("query for unknown channel $channel...");
        return undef;
    }

    print Dumper($self->{ channels }{$channel});

    return keys %{ $self->{ channels }{ $channel } };
}

sub _process_join
{
    # Called by Gutta::Dispatcher when recieved a JOIN notice from the irc
    # server.
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    $log->debug("Proccesing channel join for $nick on $channel");

    # create a hash and put known data in there.
    my %nick_data = (
       nick => $nick,
       mask => $mask,
    );

    # then send the ref here
    $self->_join_nick_to_channel($nick, $channel, \%nick_data);
}

sub _process_part
{
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    $log->debug("Proccesing channel part for $nick on $channel");

    lock($self);
    delete  $self->{channels}{$channel}{$nick};
}

sub _process_quit
{
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    # 1. Unassociate $nick from all the chanels 
    # 2. that's it !!
    
    foreach my $channel (keys %{$self->{ channels }})
    {
        if (exists $self->{ channels }{ $channel }{ $nick })
        {
            $self->_process_part($nick, $mask, $channel);
        }
    }
}

1;
