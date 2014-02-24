package Gutta::Plugin;
use Storable;
use strict;
use warnings;


sub new 
{
    my $class = shift;
    my $self = bless {
          data => {},
      datafile => undef,
    }, $class;
    $self->_initialise();
    return $self;
}

sub process_msg
{
    #  process incoming messages
    my $self = shift;
    return ();
}

sub _initialise
{
    # called when plugin is istansiated
    my $self = shift;
    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",
}

sub load
{
    # load $self->{data} from file
    my $self = shift;
    $self->save() unless -f $self->{datafile};
    $self->{data} = retrieve($self->{datafile});

}

sub save
{ 
    # save $self->{data} to file
    my $self = shift;
    store \%{$self->{data}}, $self->{datafile};
}

sub heartbeat
{
    # the plugins can handle heartbeats to act upon things outside of the irssi

}


1;
