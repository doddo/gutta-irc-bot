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

use File::Basename;
chdir(dirname(__FILE__));

use Data::Dumper;
use Gutta::AbstractionLayer;

my $server = "server";
my $msg = shift;
my $nick = "nickysthlm";
my $mask = "*";
my $target = "#test123123";



my $d = Gutta::AbstractionLayer->new();


my @r = $d->process_msg (
    $server,
    $msg,
    $nick,
    $mask,
    $target,
);

print Dumper(@r);

