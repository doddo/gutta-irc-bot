#!/usr/bin/perl
package Gutta::Init;
use strict;
use warnings;
use Data::Dumper;
use Gutta::DBI;
use Log::Log4perl;

=head1 NAME

Gutta::Init

=head1 SYNOPSIS

Initialize gutta runtime environment.

=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);


my $db = "Gutta/Data/session.db";



# remove the old data file and create a new one.
# this one should be called before any plugins starts instantiating.

if ( -e $db )
{
    $log->debug("removing old session db file...");
    unlink ( $db ) or die $!;
}




my $dbh = DBI->connect("dbi:SQLite:dbname=${db}","","")
         || die "Cannot connect to database: $DBI::errstr";

# Gutta::Context going to have this session db which contains things that is good for all the plugins
# to know.
#

1;
