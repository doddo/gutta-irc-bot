package Gutta::Plugin;
use Storable;
use strict;
use warnings;
use DateTime;


sub new 
{
    my $class = shift;
    my $self = bless {
                data => {},
            datafile => undef,
     heartbeat_act_s => 58, # default act on heartbeats ~ every 58 secs.
    heartbeat_act_dt => DateTime->new( year=>2000),
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
    my $self = shift;
    
    my $nowt = DateTime->now();
    if ($nowt->subtract_datetime_absolute($self->{heartbeat_act_dt})->delta_seconds 
                >=   $self->{heartbeat_act_s})
    {
        $self->{heartbeat_act_dt} = $nowt;
        $self->_heartbeat_act;
    }
}

sub _heartbeat_act
{
    # here is acting to the heartbeats. the plugins wanna override 
    # this function, but the mechanics for *when* to act 
    # pretty much should be the same
    #
    # This is a void function. Data collected here
    # gets returned by called from heartbeat_res for every connected
    # to server
    


}


sub heartbeat_res
{
    # Here process irc commands from the plugin from each connected to server
    # The heartbeat sets the date, the result returns it
    my $self = shift;
    my $servername = shift;

}


1;
