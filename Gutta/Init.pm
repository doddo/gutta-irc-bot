#!/usr/bin/perl
package Gutta::Init;
use strict;
use warnings;
use Data::Dumper;
use Gutta::DBI;
use Log::Log4perl;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(guttainit);


=head1 NAME

Gutta::Init

=head1 SYNOPSIS

Initialize gutta runtime environment.

=cut

my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub guttainit
{
    # This is the Gutta::Context:s db schema.
    # it gets recreated each and every time gutta is loaded.

    my $db = "Gutta/Data/session.db";

    $log->info("Resetting the session db");

    # remove the old data file and create a new one.
    # this one should be called before any plugins starts instantiating.

    if ( -e $db )
    {
        $log->debug("removing old session db file...");
        unlink ( $db ) or die $!;
    }


    my $dbh = DBI->connect("dbi:SQLite:dbname=${db}","","")
             || die "Cannot connect to database: $DBI::errstr";



    $dbh->do($_) foreach q{
        CREATE TABLE pluginmeta (
                 plugin_name TEXT NOT NULL,
                       value TEXT NOT NULL,
                  what_it_is TEXT NOT NULL,
        CONSTRAINT plugin_c UNIQUE (plugin_name, value, what_it_is) ON CONFLICT REPLACE

        )}, q{
        CREATE TABLE channels (
                 nick TEXT NOT NULL,
              channel TEXT NOT NULL,
        CONSTRAINT one_nick_per_chan UNIQUE (nick, channel) ON CONFLICT REPLACE
        );};

    $dbh->disconnect;



    # Gutta::Context going to have this session db which contains things that is good for all the plugins
    # to know.
    #


    # Other initalisation may go here.
}

1;
