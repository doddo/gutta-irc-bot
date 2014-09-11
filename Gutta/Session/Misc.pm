package Gutta::Session::Misc;
use strict;
use warnings;
use Data::Dumper;
use Log::Log4perl;
# Misc settings for the running IRC session.


my $log = Log::Log4perl->get_logger(__PACKAGE__);


sub new
{
    my $class = shift;
    my $self  = bless { }, $class;


    return $self;
}

sub set_plugincontext
{
    # Sets the plugins commands and triggers, and saves them.
    my $self = shift;
    my $plugin_ref = shift;
    my $what_it_is = shift;
    my @payload = @_;

    $log->debug("Setting context keys for $plugin_ref -> $what_it_is");

    #push (@{$self->{ plugincontext }->{$what_it_is}->{$plugin_ref}}, @payload);

    foreach (@payload)
    {
        $self->{ plugincontext }->{$what_it_is}->{$_} = $plugin_ref;
    }


}

sub get_plugin_commands
{
    # Return a list of al the commands registered from the plugins
    my $self = shift;

    return $self->{ plugincontext }->{ 'commands' };
    
}

1;
