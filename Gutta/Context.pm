#!/usr/bin/perl
package Gutta::Context;
use strict;
use warnings;
use Data::Dumper;
use Gutta::DBI;
use Gutta::Parser;
use Gutta::Constants;
use Log::Log4perl;

=head1 NAME

Gutta::Context

=head1 SYNOPSIS

This module is deprecated.
The Gutta::Context keeps track of everything the bot knows from the IRC serves and Plugins.

=head1 DESCRIPTION

Gutta::Context contains real-time information about everything gutta the IRC bot knows. This includes but is not
lgmited to  what channels the bot have joined, what nicks are in that channel. If the server have said anything "of value" about a nick
then the Gutta::Context shall keep track of this for Gutta aswell.

In addition to this, some plugins may need some information about eachother, and such knowledge are provided by the Gutta::Context.

This information gets fed into the Plugins through Gutta::Context, so if they need to know what nicks have joined a channel or something, then this Gutta::Context
will keep track of this for them.

Gutta::Abstractionlayeractively feeds this information into the plugins since they use threads and NEED the latest info. If they don't


=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);
my $parser = Gutta::Parser->new();

sub new
{
    my $class = shift;
    my $self  = bless { }, $class;

    $self->{ dbfile } = Gutta::Constants::SESSIONDBFILE;

    return $self;
}

sub dbh
{
    my $self = shift;
    my $db = $self->{ dbfile };
    $self->{ dbh } ||= DBI->connect("dbi:SQLite:dbname=${db}","","")
         || die "Cannot connect to database: $DBI::errstr";
     return $self->{ dbh };
}


sub _set_nicks_for_channel
{
    # Set who joins or a channel
    my $self = shift;
    my $server = shift;
    my $channel = shift;
    my @nicks = @_;

    my $dbh = $self->dbh();

    # Turn off autocommit
    $dbh->{AutoCommit} = 0;

    if ($dbh->{AutoCommit} != 0)
    {
       $log->warn('Could not disable AutoCommit, transactions are unavailable');
    }

    # start transaction
    #$dbh->begin_work; 
    
    # Prepare sqls.
    my $sth  = $dbh->prepare(q{
        INSERT OR IGNORE INTO nicks (nick) VALUES(?)
    });

    my $sth2 = $dbh->prepare(q{
        INSERT INTO channels(channel,nick,op,voice) VALUES(?,?,?,?)
    });

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
        $sth->execute($nick);
        $sth2->execute($channel, $nick, $op, $voice);
    }


    $dbh->commit(); # or $dbh->rollback();

    $dbh->{AutoCommit} = 1;
   

}

sub get_nicks_from_channel
{
    # Get who joins channel #channe
    my $self = shift;
    my $server = shift;
    my $channel = shift;
    my $nicks;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare(q{
       SELECT nick, op, voice FROM channels WHERE channel = ?

    }); 
    $sth->execute($channel);

    $nicks = $sth->fetchall_hashref(qw/nick/);


    return $nicks;
}

sub _process_part
{
    # remove a nick from the channel listings
    my $self = shift;
    my $server = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    my $dbh = $self->dbh();
    
    my $sth = $dbh->prepare(q{
        DELETE FROM channels WHERE nick = ? AND channel = ?
    });

    $sth->execute($nick, $channel);

}

sub _process_quit
{
    # remove a nick who just quit.
    my $self = shift;
    my $server = shift;
    my $nick = shift;
    my $mask = shift;

    my $dbh = $self->dbh();
    
    my $sth = $dbh->prepare(q{
        DELETE FROM channels WHERE nick = ?
    });

    $sth->execute($nick);

    $sth = $dbh->prepare(q{
        DELETE FROM nicks WHERE nick = ?
    });

    $sth->execute($nick);

}

sub _process_join
{
    # add a nick who've joined.
    my $self = shift;
    my $server = shift;
    my $nick = shift;
    my $mask = shift;
    my $channel = shift;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare(q{
        INSERT OR REPLACE into nicks (nick, mask) VALUES(?,?)
    });
    $sth->execute($nick, $mask);
    
    $sth = $dbh->prepare(q{
        INSERT INTO channels (nick, channel) VALUES(?,?)
    });

    $sth->execute($nick, $channel);

}


