package Gutta::Plugins::Aop;
use parent Gutta::Plugin;
use Gutta::Users;
use Gutta::Context;
use strict;
use warnings;
use Data::Dumper;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# This is still the STUB...


sub on_join
{
    my $self = shift;
    my $timestamp = shift;
    my $server = shift;
    my @payload = @_;    

    # they need someonw to aop
    $log->info(Dumper(@payload));

    return "";
}

sub process_msg
{
    my $self = shift;


    return "";
}

sub _event_handlers
{
    my $self = shift;
    return {

        'JOIN' => sub { $self->on_join(@_) },

    }
}

sub _commands
{
    my $self = shift;
    return {

        'aop' => sub { $self->process_cmd(@_) },

    }
}

1;
