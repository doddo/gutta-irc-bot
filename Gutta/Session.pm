package Gutta::Session;
use warnings;
use strict;
use parent 'Class::Singleton';

use Data::Dumper;

use threads;
use threads::shared;

use Scalar::Util;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

Gutta::Session

=head1 SYNOPSIS

Holds global run-time info.


=head1 DESCRIPTION

As soon as the bot finds out something which may be of use to for example plugins, it is kept here.

This can be for example what plugins are loaded, what channels are joined, what nicks are on those
channels and what modes the nicks have on the channels joined.

As soon as new info is found out, such as hostmask, or someone joins or parts, the Session data 
gets updated with this new information.

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

sub _update_nick
{
    # update or add nick information about nick.
    #   

    my $self = shift;
    my $nick = shift;
    my $nick_data = shift; # <-- this is hash ref...

    lock($self);
    my $nicks = \%{$self->{ nicks }};

    unless (exists $$nicks{$nick})
    {
        # Add new info about this nick ...
        my %p :shared;
        $$nicks{$nick} = \%p;
        $log->debug("Learned about $nick for the first time...");
    }
    my $nick_ref = \%{$self->{ nicks }{$nick}};
    while ( my ($key, $value) = each(%$nick_data) ) {
        # Here copy and updating. This is extra logic aded right here for good
        # Logging purposes.
        if (not defined $$nick_ref{$key} && defined $value)
        {
            # If a previously unknown attribute of a nick does get known to bot, then log it
            # here, and update the nick with that information.
            $log->debug(sprintf 'I just learned that %s has "%s"="%s"', $nick, $key, $value);
            $$nick_ref{$key} = $value;
        } else {
            if ($$nick_ref{$key} ne $value && defined $value && $value ne 'mode')
            {
                # If a value which is already known changes for some reason, then log it here, and 
                # update with this new information, while at the same time logging the old value.
                $log->debug(sprintf 'I just learned that %s\'s %s have changed from  "%s" to "%s"',
                                                              $nick, $key, $$nick_ref{$key}, $value);
                $$nick_ref{$key} = $value;
            } 
        }
    }
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
        $log->info("learned about channel $channel for the first time...");
    }

    unless (exists $$vars{$channel}{$nick})
    {
        my %p: shared;
        $log->debug("adding $nick  to $channel...");
        $$vars{$channel}{$nick} = \%p;
        unless (exists $self->{ nicks }{ $nick })
        {
            # OK  create a nick entry if none is  already...
            $self->_update_nick($nick, $nick_data);
        }
    }
    
    my $nick_ref = \%{$self->{ channels }{$channel}{$nick}};

    # Copying some interesting data in here, like whether nick is op or no...
    if (defined $$nick_data{'mode'})
    {
        unless ($$nick_ref{'mode'})
        {
            $$nick_ref{'mode'} = $$nick_data{'mode'};
            $log->debug("I just learned that on channel $channel, $nick has mode $$nick_ref{'mode'}");
        } elsif ($$nick_data{'mode'} ne $$nick_ref{'mode'}) {
            $log->debug("I just learned that on channel $channel, $nick has changed  mode from $$nick_ref{'mode'} to $$nick_data{'mode'}");
            $$nick_ref{'mode'} = $$nick_data{'mode'};
        } else {

            $log->debug("Nothing new for $nick on $channel...");
        }
        
    }

    #$log->debug(Dumper($self->{ channels }{$channel}));
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
        my $mode = 0;
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

sub _set_nickinfo
{
    # add info about $nick ...
    my $self = shift;
    my $nick = shift;
    my %n;
    $n{mask} = shift;
    $n{nick} = $nick;
    my $target = shift;
    

    # Figure out best way to update info about $nick ...
    if ($target =~ /^#/)
    {
         # Checking if target is a channel
         # then we can åka snålskjuts på _join_nick_to_channel funktionen.
         $self->_join_nick_to_channel($nick, $target, \%n);
    } 
    
    $self->_update_nick($nick, \%n);


}


sub get_nickinfo
{
    my $self = shift;
    my $nick = shift;
    return $self->{ nicks }{$nick};
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

sub _process_changed_nick
{
    # Called by Gutta::Dispatcher when someone changes nick.
    my $self = shift;
    my $oldnick = shift;
    my $mask = shift;
    my $newnick = shift;

    my @chans2fix;

    # Lock self
    lock($self);

    # create a hash and put known data in there.
    my %nick_data = (
       nick => $newnick,
       mask => $mask,
    );

    # Figure out what channels the nick is joined to...
    foreach my $channel ( keys %{ $self->{ channels } } )
    {
        if ( $self->{ channels }{ $channel }{ $oldnick } )
        {
            # Found a channel here, so this needs to be updated.
            # this is because we have to keep copies of each nick so that they
            # can have different attribs like, op on different chans etc.
            $log->debug("Gonan need to update nick change for $oldnick on $channel ...");
            push ( @chans2fix, \%{ $self->{ channels }{ $channel } } );
        }
    }

    # 
    # OK, good, then update all references, renaming oldnick to newnick.
    #  AND of course, start with the nicks reference to nick ...
    #

    foreach my $nickdata (\%{ $self->{ nicks } }, @chans2fix)
    {
        # 1st check if old nick is there.
        unless (exists $$nickdata{ $oldnick })
        {
            # then what about new nick? 
            unless (exists $$nickdata{$newnick})
            {
                # OK, simply add new nick to $self->{ nickdata }.
                share %nick_data;
                $$nickdata{$newnick} = \%nick_data;
                $log->debug("Learned about $newnick (previously known as $oldnick) for the first time...");
            }
           
        } else {
            # OK old nick *was* there, so copy it over to new nick, and then delete.
            if (exists $$nickdata{ $newnick })
            {
                # here is a special situation where both the old nick, the one nick
                # changed from, and the new nick is both defined already. That is a little bit special.
                $log->error("$newnick is known to me already, so how can $oldnick change nick to it?");
                delete ($$nickdata{ $oldnick });
            }
    
            $log->debug("Processing nick change on $nickdata for $oldnick to new nick $newnick...");
            # Copy the key, newnick references oldnick
            $$nickdata{$newnick} = $$nickdata{ $oldnick };
    
            # then remove the oldnick ref.
            delete ($$nickdata{ $oldnick });
    
            # and put the newest data in the newnick..
            $$nickdata{$newnick}{ nick } = $newnick;
            $$nickdata{$newnick}{ mask } = $mask;
        }
    }
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

    lock($self);
    $log->info("handled $nick QUIT.");
    delete  $self->{ nicks }{$nick};

}

1;
