#!/usr/bin/perl
package Gutta::Init;
use strict;
use warnings;
use Data::Dumper;
use Gutta::Constants;
use Gutta::DBI;
use Log::Log4perl;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(guttainit guttacleanup);


=head1 NAME

Gutta::Init

=head1 SYNOPSIS

Initialize gutta runtime environment.

=cut


sub guttainit
{
    my $log = Log::Log4perl->get_logger(__PACKAGE__);

    # This is the Gutta::Context:s db schema.
    # it gets recreated each and every time gutta is loaded.
    $log->info('Initialising gutta runtime environment...');

    my $db = Gutta::Constants::SESSIONDBFILE;

    $log->info("Creating the session db: '$db'");


    # remove the old data file and create a new one.
    # this one should be called before any plugins starts instantiating.

    if ( -e $db )
    {
        $log->warning("session db file '$db' exists already...");
    }


    my $dbh = DBI->connect("dbi:SQLite:dbname=${db}","","")
             || die "Cannot connect to database: $DBI::errstr";



    $dbh->do($_) foreach q{
         CREATE TABLE IF NOT EXISTS pluginmeta (
          plugin_name TEXT NOT NULL,
                value TEXT NOT NULL,
           what_it_is TEXT NOT NULL,
           CONSTRAINT plugin_c UNIQUE (plugin_name, value, what_it_is) 
                   ON CONFLICT REPLACE
        )}, q{
         CREATE TABLE IF NOT EXISTS nicks (
                 nick TEXT PRIMARY KEY,
                modes TEXT,
                 mask TEXT
        )}, q{
         CREATE TABLE IF NOT EXISTS channels (
                 nick TEXT NOT NULL,
              channel TEXT NOT NULL,
                   op INTEGER DEFAULT 0,
                voice INTEGER DEFAULT 0,
              FOREIGN KEY(nick) REFERENCES nicks(nick),
           CONSTRAINT one_nick_per_chan UNIQUE (nick, channel) ON CONFLICT REPLACE
        )}, q{
         CREATE TABLE IF NOT EXISTS server_info (
               server TEXT NOT NULL,
                  key TEXT NOT NULL,
                value TEXT NOT NULL,
          PRIMARY KEY (server, key) ON CONFLICT REPLACE
        )};

    $dbh->disconnect;


    # Gutta::Context going to have this session db which contains things that is good for all the plugins
    # to know.
    #


    # Other initalisation may go here.
}

sub guttacleanup
{
    my $log = Log::Log4perl->get_logger(__PACKAGE__);
    # Clean up after the proces've been killed...
    my $db = Gutta::Constants::SESSIONDBFILE;

    if ( -e $db )
    {
        $log->info("Removing session db file '$db'.");
        unlink ( $db ) or $log->warn($!);
    }

}


1;
