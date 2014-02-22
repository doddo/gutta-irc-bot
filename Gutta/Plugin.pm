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
    my $self = shift;
    return ();
}

sub _initialise
{
    my $self = shift;
    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",
}

sub load
{
    my $self = shift;
    $self->save() unless -f $self->{datafile};
    $self->{data} = retrieve($self->{datafile});

}

sub save
{ 
    my $self = shift;
    store \%{$self->{data}}, $self->{datafile};
}


1;
