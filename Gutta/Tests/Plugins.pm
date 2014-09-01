package Gutta::Tests::Plugins;

use Pod::Usage;

use Test::More tests => 22;

use strict;
use warnings;



# Instantiate all the plugins.
use Module::Pluggable search_path => "Gutta::Plugins",
                          require => 1;
#



foreach my $plugin (plugins())
{

    $plugin->new();

    ok( defined $plugin, "Test if  $plugin  defined..." );
    ok( $plugin->isa('Gutta::Plugin'), "Test if $plugin is a Gutta::Plugin..." ); 

}


1;
