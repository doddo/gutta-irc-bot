#!/usr/bin/perl
# == WHAT
# All around bot "Gutta".
#
# == WHO
# Based on "All around bot" by Jeroen Van den Bossche, 2012
# Fork By PETTER H 2014
#
# == INSTALL
# Save the whole thing under ~/.irssi/scripts/ and then run irssi, and /load gutta.pl
# OR
# Save it in ~/.irssi/scripts/autorun and (re)start Irssi

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


sleep(2);

my @irc_cmds = $d->plugin_res(999);
$log->info(sprintf" < %s", $_) foreach @irc_cmds;
