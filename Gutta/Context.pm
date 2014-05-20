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

sub update_context
{
    my $self = shift;
    #trigger this under some circumstances,
    # it may be certain messages from the IRC server, like JOIN, PART
    # QUITS and so forth.
    # Keep this stored somewhere.
    
}

sub set_plugincontext
{
    my $self = shift;
    my $plugin_name = shift;
    my $what_it_is = shift;
    my @payload = @_;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('INSERT INTO pluginmeta (plugin_name, what_it_is, value) VALUES(?,?,?)');

    foreach my $value (@payload)
    {
        $log->debug("setting $what_it_is for $plugin_name: $value");
        $sth->execute($plugin_name, $what_it_is, $value);
    }
}

sub get_plugin_commands
{
    my $self = shift;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('SELECT plugin_name, value FROM pluginmeta where what_it_is = "commands"');

    $sth->execute();

    my $r = $sth->fetchall_hashref('value');

    return $r;
    
}
