#!/usr/bin/perl
package Gutta::Context;
use strict;
use warnings;
use Data::Dumper;
use Gutta::DBI;
use Log::Log4perl;

=head1 NAME

Gutta::Context

=head1 SYNOPSIS

Using the Gutta::Parser etc, the Gutta::Context keeps track of everything the bot knows from the IRC serves and Plugins.

=head1 DESCRIPTION

Gutta::Context contains real-time information about everything gutta the IRC bot knows. This includes but is not
limited to  what channels the bot have joined, what nicks are in that channel. If the server have said anything "of value" about a nick
then the Gutta::Context shall keep track of this for Gutta aswell.

In addition to this, some plugins may need some information about eachother, and such knowledge are provided by the Gutta::Context.

This information gets fed into the Plugins somehow, so if they need to know what nicks have joined a channel or something, then this Gutta::Context
will keep track of this for them.

I think Gutta::Abstractionlayer needs to actively feed this information into the plugins since they use threads and NEED the latest info. If they don't
get it from the database instead, TBD.

THIS IS YET A STUB.


=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub new
{
    my $class = shift;
    my $self  = bless { }, $class;

    $self->{ dbfile } = "Gutta/Data/session.db";

    # get a db handle for internal use.
    $self->{internaldbh} = $self->dbh();

    return $self;
}

sub dbh
{
    my $self = shift;
    my $db = $self->{ dbfile };
    $self->{ dbh } = DBI->connect("dbi:SQLite:dbname=${db}","","")
         || die "Cannot connect to database: $DBI::errstr";
     return $self->{ dbh };
}

sub  swipeinit_sessiondb
{
    # the function to remove the old data file and create a new one.
    # this one should be called before any plugins starts instantiating.
    my $self = shift;

    if ( -e $self->{ dbfile })
    {
        $log->debug("removing old session db file...");
        unlink ( $self->{ dbfile }) or die $!;
    }
    
    my $dbh = $self->{ internaldbh };
    my $sth;

    my @queries = (qq{
     CREATE TABLE  plugins_commands (
        plugin_name TEXT NOT NULL,
            command TEXT NOT NULL
      PRIMARY KEY (plugin_name, command) ON CONFLICT REPLACE

    )}, qq{
     CREATE TABLE plugins_triggers (
        plugin_name TEXT NOT NULL,
            trigger TEXT NOT NULL
      PRIMARY KEY (plugin_name, trigger) ON CONFLICT REPLACE
    )}, qq{
     CREATE TABLE nicks (
               nick TEXT NOT NULL,
            channel TEXT NOT NULL
      PRIMARY KEY (nick, channel) ON CONFLICT IGNORE
    )} );


    foreach my $query (@queries)
    {
        $sth = $dbh->prepare($query) or die "unable to run: $query\n";
        $sth->execute() or  die "unable to execute; $query\n:  $dbh->errstr;";
    }

}




sub update_context
{
    my $self = shift;
    #trigger this under some circumstances,
    # it may be certain messages from the IRC server, like JOIN, PART
    # QUITS and so forth.
    # Keep this stored somewhere.
    

    

}


sub set_plugin_to_commandsmap
{
    my $self;
    my $commands = shift;

    my $dbh = $self->{ db }->dbh();



    my $sth


}


