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

sub _triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;

    return {
        qr/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/ => sub { $self->give_karma(@_) },
    };
}

sub _commands
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
    return "kalle koma now has X points of coma\n";

}

sub give_karma
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $match = shift;

    return sprintf 'msg %s %s now has 666 points of coma', $target, $nick

}


1;
