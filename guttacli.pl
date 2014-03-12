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

use Module::Pluggable search_path => "Gutta::Plugins",
                      instantiate => 'new';
use File::Basename;
chdir(dirname(__FILE__));

use Data::Dumper;


my $nick = shift;
my $target = shift;
my $msg = shift;
my $mask = "";

my @PLUGINS  = plugins();

    foreach my $plugin (@PLUGINS) 
    {
        foreach my $command ($plugin->process_msg($msg, $nick, $mask, $target))
        {
            if ($command)
            {
                print "$command\n";
            }
        }
    }

