#!/usr/bin/perl
# Guttacli stub.
# 
# The guttacli can (in the future) interface with running gutta session through
# An admin socket.
#

use strict;
use warnings;

use Log::Log4perl;

use File::Basename;
chdir(dirname(__FILE__));


Log::Log4perl->init("Gutta/Config/Log4perl.conf");
my $log = Log::Log4perl->get_logger();

use Data::Dumper;
use Gutta::AbstractionLayer;

my $server = "server";
my $msg = shift;
my $nick = "nickysthlm";
my $mask = "*";
my $target = "#test123123";

my $d = Gutta::AbstractionLayer->new();

my @r = $d->process_privmsg (
    $server,
    $msg,
    $nick,
    $mask,
    $target,
);

foreach (@r)
{
    $log->info(sprintf" < %s", $_);
}
 

for (my $i=0;$i<5;$i++)
{
    foreach ($d->plugin_res(999))
    {
        $log->info(sprintf" < %s", $_);
    }
    sleep 1;
}

