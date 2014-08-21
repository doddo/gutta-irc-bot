package Gutta::Plugins::Karma;
use parent Gutta::Plugin;
use Gutta::DBI;
use Data::Dumper;
# A module to to manage karma
use strict;
use warnings;

=head1 NAME

Gutta::Plugins::Karma

=head1 SYNOPSIS

Give karma-- to someone++

=head1 DESCRIPTION

Like most IRC bots, Gutta::IRC::Bot tracks karma. You give or remove karma points with the ++ and -- operators. Karma can be checked with the rank command. 

=head1 rank

rank something, to see the karma (but not the rank yet). if something is omitted, print who is on top.

!rank something

=head1 srank

print the top 10 entries like something. if something is omitted, print instead top 10 list. 

!srank [ something ]

=cut 


my $log = Log::Log4perl->get_logger(__PACKAGE__);


sub _initialise
{
    my $self = shift;
    $self->_dbinit();
}

sub _setup_shema 
{
    my $self = shift;

    my @queries  = (qq{
    CREATE TABLE IF NOT EXISTS karma_table (
            item TEXT PRIMARY KEY,
            karma INTEGER DEFAULT 0
    )}, qq{
    CREATE VIEW IF NOT EXISTS karma_toplist AS
        SELECT item,
               karma,
               (
                SELECT COUNT(*) + 1
                FROM karma_table AS t2
                WHERE t2.karma > t1.karma
               ) AS rank
        FROM karma_table AS t1
        ORDER BY karma DESC;
    });

    return @queries;
 
}

sub _triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;

    return {
           qr/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/i => sub { $self->give_karma(@_) },
                                   qr/^srank\b/  => sub { $self->srank('srank',@_) },
                                    qr/^rank\b/  => sub { $self->srank('rank',@_) },
    };
}

sub _commands
{
    # The dispatch table for "commands" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;

    return {
           'srank' => sub { $self->srank('srank', @_) },
           'rank'  => sub { $self->srank('rank', @_) },
    };
}


sub srank
{
    my $self = shift;
    $log->info("got this " . Dumper(@_));
    my $action = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $match = shift;
    my $query;    

    # get the db handle.
    my $dbh = $self->dbh();

    # the array of respnoses to pass back to the caller
    # this is an array of IRC commands.
    my @responses;

    my $target_item;

    if ($action eq 'srank')
    {
        # fetch what item to target from msg
        # msg looks like ~ this "srank foo"
        if ($msg =~ m/^srank(?:\s+(\S+))?\b/)
        {
            $target_item = ($1) ?  "%${1}%" : '%%';
        } else {
            $target_item = ($match) ?  "%${match}%" : '%%';
        }

        $query = qq{
            SELECT item, karma, rank FROM karma_toplist
             WHERE item LIKE ?
             LIMIT 6
          };
    
    } else {
        # fetch what item to target from msg
        # msg looks like ~ this "rank foo"
        if ($msg =~ m/^rank(?:\s+(\S+))?\b/)
        {
            $target_item = ($1) ?  ${1} : '';
            
        } else {
            $target_item = ($match) ?  ${match} : '';
        }
        $query = qq{
            SELECT item, karma, rank FROM karma_toplist
             WHERE item = ?
          };
    }
    $log->debug("$action called for \"$target_item\"...");
    
    # List top 10 karma items matching $target_item
    my $sth = $dbh->prepare($query);
    $sth->execute($target_item);    

    # run the query
    #
    #
    # forma t response based on query (and context)
    
    while ( my($item, $karma, $rank) = $sth->fetchrow_array())
    {
        push @responses, sprintf 'msg %s %-9s (%i) (rank %i)', $target, $item, $karma, $rank;
    }

    # What shall we say of there is nothing to say? Nothing I guess.

    $log->debug(sprintf "returning %i rows of karma", scalar @responses);

    return @responses;

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

    my $dbh = $self->dbh();

    # the array of respnoses to pass back to the caller
    # this is an array of IRC commands.
    my @responses;

    # OK parse the $msg (could be done better in the future)
    while ($msg =~ s/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)//i)
    {
        my $item = lc($1);
        my $modifier = lc($2);
        my $value;

        # compute wheter karma for item should be incremented
        # or decremented.
        if (($item ne lc($nick)) and ($modifier eq '++'))
        {
            $value = 1;
        } else {
            $value = -1;
        }
       
        #  TODO: FIX THSI BETTER LATER
        my $sth = $dbh->prepare("INSERT OR IGNORE INTO karma_table (item) VALUES (?)");
        $sth->execute($item);
        $sth = $dbh->prepare("UPDATE karma_table SET karma = karma +? WHERE item = ?");
        $sth->execute($value,$item);
        $sth = $dbh->prepare("SELECT karma, rank FROM karma_toplist WHERE item = ?");
        $sth->execute($item);
        
        # And then get the value (karma) from the SELECT
        my ($karma, $rank) = $sth->fetchrow_array() or warn $dbh->errstr;

        # and then finally, push the responses
        push @responses, sprintf 'msg %s %s now has %i points of karma (rank %i).', $target, $item, $karma, $rank;

    }

    return @responses;

}

1;
