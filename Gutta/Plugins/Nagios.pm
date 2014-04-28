package Gutta::Plugins::Nagios;
# does something with Nagios

use parent Gutta::Plugin;

use HTML::Strip;
use LWP::UserAgent;
use XML::FeedPP;
use MIME::Base64;
use JSON;
use strict;
use warnings;
use Data::Dumper;
use DateTime::Format::Strptime;
use Getopt::Long qw(GetOptionsFromArray);
use Switch;


=head1 NAME

Gutta::Plugins::Nagios


=head1 SYNOPSIS

Provides Nagios connection to gutta bot


=head1 DESCRIPTION

Add support to have gutta check the nagios rest api for hostgroup status and send any alarms encounterd into the target channel or channels.

say this:

 '!monitor config --username monitor --password monitor --nagios-server 192.168.60.182'

to configure a connection to monitor at 192.168.60.182 using username monitor and password monitor.

Then start using it:

!monitor hostgroup unix-servers --irc-server .* --to-channel #test123123

To add op5 irc monitoring for all servers in the unix-servers hostgroups on all servers, and send messages Crit, Warns and Clears to channel #test123123

Similarly

!unmoniutor hostgroup unix-servers

will remove monitoring for said server

Also you can do this:

!monitor host <hostid> --irc-server .* --to-channel #test123123

to add a single host.

=cut

my $log;

sub _initialise
{
    # called when plugin is istansiated
    my $self = shift;
    # The logger
    $log = Log::Log4perl->get_logger(__PACKAGE__);

    # initialise the database if need be.
    $self->_dbinit();

    # this one should start in its own thread.
    $self->{want_own_thread} = 1;
}

sub _commands
{
    my $self = shift;
    # the commands registered by this pluguin.
    #
    return {
        "monitor" => sub { $self->monitor(@_) },
      "unmonitor" => sub { $self->unmonitor(@_) },
    }
}

sub _setup_shema
{
    my $self = shift;

    my @queries  = (qq{
    CREATE TABLE IF NOT EXISTS monitor_hostgroups (
         irc_server TEXT NOT NULL,
            channel TEXT NOT NULL,
          hostgroup TEXT NOT NULL,
         last_check INTEGER DEFAULT 0,
      CONSTRAINT uniq_hgconf UNIQUE (irc_server, channel, hostgroup)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_hosts (
         irc_server TEXT NOT NULL,
            channel TEXT NOT NULL,
               host TEXT NOT NULL,
         last_check INTEGER DEFAULT 0,
      CONSTRAINT uniq_hconf UNIQUE (irc_server, channel, host)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_hoststatus (
          host_name TEXT PRIMARY KEY,
         hard_state INTEGER NOT NULL,
      plugin_output TEXT NOT NULL,
            address TEXT NOT NULL,
     from_hostgroup INTEGER NOT NULL
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_servicedetail (
          host_name TEXT PRIMARY KEY,
            service TEXT NOT NULL,
              state INT NOT NULL,
   has_been_checked INT NOT NULL,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name)
    )});

    return @queries;

}


sub monitor
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
    # they need something to monitor.
    return unless $rest_of_msg;

    my @irc_cmds;

    # get the commands.
    my ($subcmd, @values) = split(/\s+/, $rest_of_msg);

    switch (lc($subcmd))
    {
        case 'hostgroup' { @irc_cmds = $self->_monitor_hostgroup(@values) }
        case      'host' { @irc_cmds = $self->_monitor_host(@values) }
        case    'config' { @irc_cmds = $self->_monitor_config(@values) }
        case      'dump' { @irc_cmds = $self->_monitor_login(@values) }
    }

    return map { sprintf 'msg %s %s: %s', $target, $nick, $_ } @irc_cmds;
}

sub _monitor_hostgroup
{
    my $self = shift;
    my $hostgroup = shift;
    my @args = @_;

    my $server;
    my $channel;

    my $ret = GetOptionsFromArray(\@args,
        'irc-server=s' => \$server,
        'to-channel=s' => \$channel,
    ) or return "invalid options supplied.";

    $log->debug("setting up hostgroup config for $channel on server(s) mathcing $server\n");

    return;
}

sub _monitor_config
{
    # Configure monitor, for example what nagios server is it?
    # who is the user and what is the password etc etc
    my $self = shift;
    my @args = @_;
    my %config;

    my $ret = GetOptionsFromArray(\@args, \%config,
           'username=s',
           'password=s',
     'check-interval=s',
      'nagios-server=s',
    ) or return "invalid options supplied:";
    
    while(my ($key, $value) = each %config)
    {
        $log->info("setting $key to $value for " . __PACKAGE__ . ".");
        $self->set_config($key, $value);
    }

    return 'got it.'
}

sub unmonitor
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
    # they need someonw to slap
    return unless $rest_of_msg;


    return;
}




1;
