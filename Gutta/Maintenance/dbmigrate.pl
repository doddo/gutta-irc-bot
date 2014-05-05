#!/usr/bin/perl
#
#
# THE DB MIGRATE TOOL
# Can migrade schema from any released version to latest.
#
use strict;
use warnings;
use Gutta::DBI;

our $TARGET_SCHEMA = 1;
my $sth;

my $dbi = Gutta::DBI->instance();

my $dbh = $dbi->dbh();

$sth = $dbh->prepare('PRAGMA user_version');
$sth->execute();

my ($user_version) = $sth->fetchrow_array();

if ($TARGET_SCHEMA == $user_version)
{
    print "Nothing needs to be done - schema version already at $user_version.\n";

}


if ($user_version < 1)
{
    # Add extra field for nagios plugin
    #

    my $sth = $dbh->prepare("ALTER TABLE monitor_servicedetail ADD COLUMN is_flapping INTEGER DEFAULT 0");
    $sth->execute();
}

$sth = $dbh->do("PRAGMA user_version = $TARGET_SCHEMA");
