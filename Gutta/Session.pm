package Gutta::Session;
use warnings;
use strict;
use vars qw(@ISA);
our @ISA = qw(Class::Singleton);

use Gutta::Session::Misc;
use Gutta::Session::Nick;
use Data::Dumper;



my $log = Log::Log4perl->get_logger(__PACKAGE__);
my $misc = Gutta::Session::Misc->new();


=head1 NAME

Gutta::Session

=head1 SYNOPSIS

Holds info which is shared between classes etc. This gonan replace Gutta::Context


=head1 DESCRIPTION

Most of the things known by gutta will be stored here for later use.

=cut



sub set_plugincontext
{
    my $self = shift;
    $misc->set_plugincontext(@_);

}

sub get_plugin_commands
{
    # Return a list of al the commands registered from the plugins
    my $self = shift;

    return $misc->get_plugin_commands(@_);
}


1;
