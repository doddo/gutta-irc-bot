#!/usr/bin/perl
#
#
# THE DB MIGRATE TOOL
# Can migrade schema from any released version to latest.
#
use strict;
use warnings;
use Gutta::DBI;
use Data::Dumper;
our $TARGET_SCHEMA = 1;
my $sth;
my @errors;

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

    my $sth = $dbh->do(qq{
            ALTER TABLE monitor_hoststatus ADD COLUMN is_flapping INTEGER DEFAULT 0;
            ALTER TABLE monitor_servicedetail ADD COLUMN is_flapping INTEGER DEFAULT 0
     }) or push @errors, $dbh->errstr();
    
}


if (scalar @errors > 0) {
    print "OOPs follwong things failed, manual intervention required:\n";
    print Dumper(@errors);
    exit 24;
} else {
    $sth = $dbh->do("PRAGMA user_version = $TARGET_SCHEMA");
}
print "OK.\n";
