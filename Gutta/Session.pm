package Gutta::Session;
use warnings;
use strict;
use vars qw(@ISA);
our @ISA = qw(Class::Singleton);

use Gutta::Session::Misc;
use Gutta::Session::Nick;
use Data::Dumper;



my $log = Log::Log4perl->get_logger(__PACKAGE__);
my $misc = Gutta::Session::Misc->new();


=head1 NAME

Gutta::Session

=head1 SYNOPSIS

Holds info which is shared between classes etc. This gonan replace Gutta::Context


=head1 DESCRIPTION

Most of the things known by gutta will be stored here for later use.

=cut



sub set_plugincontext
{
    my $self = shift;
    $misc->set_plugincontext(@_);

}

sub get_plugin_commands
{
    # Return a list of al the commands registered from the plugins
    my $self = shift;

    return $misc->get_plugin_commands(@_);
}

sub get_foo
{
    my $self = shift;
    return join ",", @{$self->{foo}};
}

sub set_foo
{
    my $self = shift;
    my $what = shift;
    push @{$self->{foo}}, $what;
}


sub _set_nicks_for_channel
{
    # Set who joins or a channel
    my $self = shift;
    my $server = shift;
    my $channel = shift;
    my @nicks = @_;

    unless($self->{channels}{$channel})
    {
        $log->debug("setting up new channel $channel...");
        %{$self->{channels}->{$channel}} = ();
    }


    foreach my $nick (@nicks)
    {
        my $op = 0;
        my $voice = 0;
        # Check if nick is an operator or has voice
        if ($nick =~ s/^([+@])//)
        {
            if ($1 eq '@')
            {
                $op = 1;
            } else {
                $voice = 1; 
            }
        }
        $log->info("'$nick' is joined to '$channel'...");

        $self->{nicks}{$nick} ||= Gutta::Session::Nicks->New();

        $self->{nicks}{$nick}->nick($nick);
        # TODO: join channel etc etch

        $self->{ channels }{ $channel }{$nick} = \$self->{nicks}{$nick};

    my @kalle = keys %{$self->{ channels }{$channel}};
        $log->info("nicks for $channel is " .  join "," , @kalle);
        
    }
}

sub get_nicks_from_channel
{
    my $self = shift;
    my $channel = shift;
    
    if ($self->{ channels }{$channel})
    {
        $log->warn("query for unknown channel $channel...");
        return undef;
    }

    map { $log->info("I got this $_") } keys %{$self->{ channels }{$channel}};
    
    $log->debug("getting infor from $channel...");
    $log->debug(Dumper(%{$self->{ channels }{$channel}}));

    my @kalle = keys %{$self->{ channels }{$channel}};

    $log->info("nicks for $channel is " .  join "," , @kalle);

    return @kalle;

}

sub _process_join
{
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    $log->debug("Proccesing channel join for $nick on $channel");
    $self->{nicks}{$nick} ||= Gutta::Session::Nick->new();

    $self->{nicks}{$nick}->nick($nick);
    $self->{nicks}{$nick}->mask($mask);
    # TODO: join channel etc etch

    unless($self->{channels}{$channel})
    {
        $log->debug("setting up new channel $channel...");
        %{$self->{channels}->{$channel}} = ();
    }

    $self->{channels}{$channel}{$nick} = \$self->{nicks}{$nick};
    my @kalle = keys %{$self->{ channels }{$channel}};
    $log->info("nicks for $channel is " .  join "," , @kalle);

    $log->debug(Dumper %{$self->{channels}->{$channel}});


}

sub _process_part
{
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    $log->debug("Proccesing channel part for $nick on $channel");
    $self->{nicks}{$nick} ||= Gutta::Session::Nicks->New();

    $self->{nicks}{$nick}->nick($nick);
    $self->{masks}{$nick}->mask($mask);
    # TODO: join channel etc etch

    delete($self->{channels}{$channel}{$nick});

}


1;
