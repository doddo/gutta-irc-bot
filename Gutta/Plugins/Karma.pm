package Gutta::Plugins::Karma;
use parent Gutta::Plugin;
use Gutta::DBI;
# A module to to manage karma
use strict;
use warnings;

sub _initialise
{
    my $self = shift;
    $self->_dbinit();
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
                                qr/^srank/ => sub { $self->srank(@_) },
                                 qr/^rank/ => sub { $self->sank(@_) },
    };
}

sub srank
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $match = shift;

    # get the db handle.
    my $dbh = $self->dbh();

    # fetch what item to target from msg
    # msg looks like ~ this "srank foo"
    $msg =~ m/^srank\s+(\S+)\b/;
    my $target_item = ($1) ?  "%${1}%" : '%%';

    # the array of respnoses to pass back to the caller
    # this is an array of IRC commands.
    my @responses;
    
    # List top 10 karma items matching $target_item
    my $sth = $dbh->prepare(q{
        SELECT item, karma FROM karma_table 
         WHERE item LIKE ? 
      ORDER BY karma DESC LIMIT 10
    });
    $sth->execute($target_item);    

    # run the query
    #
    #
    # forma t response based on query (and context)
    
    while ( my($item, $karma) = $sth->fetchrow_array())
    {
        push @responses, sprintf 'msg %s %s (%i)', $target, $item, $karma;
    }
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
    while ($msg =~ s/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)//)
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
        $sth = $dbh->prepare("SELECT karma FROM karma_table WHERE item = ?");
        $sth->execute($item);
        
        # And then get the value (karma) from the SELECT
        my $karma = $sth->fetchrow_array() or warn $dbh->errstr;

        # and then finally, push the responses
        push @responses, sprintf 'msg %s %s now has %i points of karma.', $target, $item, $karma

    }

    return @responses;

}


1;
