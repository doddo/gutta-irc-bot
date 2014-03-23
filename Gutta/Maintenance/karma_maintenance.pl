#!/usr/bin/perl
#
use strict;
use warnings;
use Storable;

my $karma_hash  = retrieve('Gutta/Data/Gutta::Plugins::Karma.data');


while (my ($item, $karma) = each ($karma_hash))
{
    while ($karma > 0)
    {
        print "$item++ \n";
        $karma--;

    }
    while ($karma < 0)
    {
        print "$item--\n";
        $karma++;

    }
}
