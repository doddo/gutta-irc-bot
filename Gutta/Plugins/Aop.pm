package Gutta::Plugins::Aop;
use parent Gutta::Plugin;
use Gutta::Users;
use Gutta::Session;
use strict;
use warnings;
use Data::Dumper;
use Switch;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

Gutta::Plugins::Aop

=head1 SYNOPSIS

Instruct bot to automatically handle op:ing nicks in channels.


=head1 DESCRIPTION

Provides support for having the bot automatically add nicks when joining and 
upon request.

=head1 aop

Handle aop:ing the incoming nick. aop:s get op.


  !aop [ add | del | modify ] NICK [ --channel C ] [ --level INT ] [ --mask M ]

=over 8

=item B<--channel>

What channel (if in a channel and ommitted, will assume it current channel)

=item B<--level>

The level is a number between 0-100. an aop can only add someone with less level
than itself has. A number above 1 means that the user will be oped, (but can't op)

=item B<--mask>

If the bot doesn't know what hostmask is associated with a nick, or the user
has not registered with register command, the mask must be manually sent to bot,
with the --mask opt.

=back

=head1 op

used to give op to a user. 
If channel is omitted, it will assume current channel.
If is omitted, it will assume current channel.

  !op [ channel ] [ nick ]

=cut

sub _setup_shema
{
    my $self = shift;

    my @queries  = (qq{
    CREATE TABLE IF NOT EXISTS aops (
            channel TEXT NOT NULL,
               nick TEXT NOT NULL,
               mask TEXT NOT NULL,
    FOREIGN KEY(nick) REFERENCES users(nick),
      CONSTRAINT nick_per_chan UNIQUE (nick, channel)
    });

    return @queries;
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


1;
