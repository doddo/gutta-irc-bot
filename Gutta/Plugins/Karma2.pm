package Gutta::Plugins::Karma2;
use parent Gutta::Plugin;
use Gutta::DBI;
# A module to to manage karma
use strict;
use warnings;

sub _initialise
{
    my $self = shift;
    $self->_dbinit('karma');
    
    $self->get_triggers();

    $self->{triggers}{"([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)"}->( "godis");
}

sub _setup_shema 
{
    my $self = shift;
    return <<EOM
    CREATE TABLE IF NOT EXISTS karma_table (
                 item TEXT PRIMARY KEY,
                 karma INTEGER DEFAULT 0
    );
EOM
;
}

sub _get_triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;
    $self->{triggers} = {
        qr/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/ => sub { $self->give_karma(@_) },
    };
    return $self->{triggers};
}

sub _get_commands
{
    # The dispatch table for "commands", which is the first word sent to Gutta
    # it may be prefixed with $CMDPREFIX in parent, depending on context:
    #   (private vs public msg)
    my $self = shift;
    $self->{triggers} = {
        'rank' => sub { $self->rank(@_) },
       'srank' => sub { $self->srank(@_) },
    };
    return $self->{triggers};
}

sub trigger
{
    my $self = shift;
    my $trigger = shift;
    #
    # DO IT (something like this)
    #
    return unless $self->{triggers};

    return $self->{triggers}{$trigger}->(@_);
}



sub rank
{
    my $self = shift;
    
    print "RANK\n"
}

sub srank
{
    my $self = shift;
    print "SRANK\n";

}

sub give_karma
{
    my $self = shift;
    my $godis = shift;
    print "GIVE_KARMA\n";
}



1;
