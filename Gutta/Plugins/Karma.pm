package Gutta::Plugins::Karma;
use parent Gutta::Plugin;
use Gutta::DBI;
# A module to to manage karma
use strict;
use warnings;

sub _initialise
{
    my $self = shift;
    $self->_dbinit('karma');

  #  $self->{triggers} = $self->_set_triggers();
  #  $self->{commands} = $self->_set_commands();

    print $self->trigger(qr/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/,"godis");
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

sub _set_triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;


    return {
        qr/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/ => sub { $self->give_karma(@_) },
    };
}

sub _set_commands
{
    # The dispatch table for "commands", which is the first word sent to Gutta
    # it may be prefixed with $CMDPREFIX in parent, depending on context:
    #   (private vs public msg)
    my $self = shift;
    return {
        'rank' => sub { $self->rank(@_) },
       'srank' => sub { $self->srank(@_) },
    };
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
    return "GIVE_KARMA $godis\n";
}



1;
