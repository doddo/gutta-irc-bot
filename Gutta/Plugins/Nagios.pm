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
              state INTEGER NOT NULL
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_servicedetail (
          host_name TEXT NOT NULL,
            service TEXT NOT NULL,
              state INTEGER DEFAULT 0,
   has_been_checked INTEGER DEFAULT 0,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name),
      CONSTRAINT uniq_service UNIQUE (host_name, service)

    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_hosts_from_hostgroup (
          host_name TEXT NOT NULL,
          hostgroup TEXT NOT NULL,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name),
    FOREIGN KEY (hostgroup) REFERENCES monitor_hostgroups(hostgroup),
      CONSTRAINT uniq_hgconf UNIQUE (host_name, hostgroup)
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
        case   'runonce' { @irc_cmds = $self->_get_hostgroups(@values) }
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

    # get a db handle.
    my $dbh = $self->dbh();

    # Insert the stuff ino the database
    my $sth = $dbh->prepare(qq{INSERT OR REPLACE INTO monitor_hostgroups
        (hostgroup, irc_server, channel) VALUES(?,?,?)}) or return $dbh->errstr;

    # And DO it.
    $sth->execute($hostgroup, $server, $channel) or return $dbh->errstr;


    return "OK - added monitoring for hostgroup:[$hostgroup] on  channel:[$channel] for servers matching re:[$server]";
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

    #TODO FIX THIS BORING.

    return;
}


sub _get_hostgroups
{
    my $self = shift;

    my $dbh = $self->dbh();

    # check what hostgroups are configured for monitoring.
    my $sth = $dbh->prepare(qq{SELECT DISTINCT hostgroup FROM monitor_hostgroups});
    $sth->execute();

    $log->debug(sprintf 'got %i hostgroups from db.', $sth->rows );

    # the hoststatus which've been fetched from the db
    my $db_hoststatus = $self->_db_get_hosts();

    # the servicestatus which've been fetched from the db.
    #

    #  After having gotten db_hoststatus and db_servicedetail, and read it into vars, now we replace
    #  the stuff in the database with what is found in the API. We'll compare them later.
    #
    #  This means that if crash here, then the data will have to be downloaded atain, but that's OK

    my $db_servicestatus = $self->_db_get_servicestatus();


    $log->warn(Dumper($db_servicestatus));

    # now remove the hostgroups from the monitor_hosts_from_hostgroup, it will need new hosts now.
    my $sth2 = $dbh->prepare('DELETE FROM monitor_hosts_from_hostgroup');
    $sth2->execute();

    # prepare a new statement to re-populate that hostgroup...
    $sth2 = $dbh->prepare('INSERT OR IGNORE INTO monitor_hosts_from_hostgroup (host_name, hostgroup) VALUES (?,?)');

    # Prepare to add a new host into monitor_hoststatus
    my $sth3 = $dbh->prepare('INSERT OR REPLACE INTO monitor_hoststatus (host_name, state) VALUES(?,?)');

    # the same service status we just are about to get from the API.
    my %api_servicestatus;

    # Status of the host (We get them from the hostgroup)
    my %api_hoststatus;

    # Loop through all the configured hostgroups, and fetch node status for them.
    while ( my ($hostgroup) = $sth->fetchrow_array())
    {
        $log->debug("processing $hostgroup.....");

        my ($rval, $payload_or_message) = $self->__get_request(sprintf '/status/hostgroup/%s', $hostgroup);

        # do something with the payload.
        if ($rval)
        {
            my $payload = from_json($payload_or_message, { utf8 => 1 });

            my $members = @$payload{'members_with_state'};
            print Dumper(@$members);
            foreach my $member (@$members)
            {
                my ($hostname, $state, $has_been_checked) = @$member;

                # create the hoststatus hash to look the same as what we got from the db earlier (hopefully)
                %{$api_hoststatus{$hostname}} = (
                               state => $state,
                    has_been_checked => $has_been_checked
                );

                $log->debug(sprintf 'got %s with state %i. been checked=%i', $hostname, $state, $has_been_checked);
                # Add to monitor_hosts_from_hostgroup (so we know what hostgroups this host belong to
                $sth2->execute($hostname, $hostgroup);
                # And insert the state of the host here.
                $sth3->execute($hostname, $state);

                # GET servicestatus from the monitor API
                %{$api_servicestatus{$hostname}} = $self->_api_get_host($hostname);
            }
        }
    }


    # Insert the host status stuff into the database...
    $self->__insert_new_hoststatus(\%api_servicestatus);


    # OK so lets compare few things.
    foreach my $hostname (keys %api_servicestatus)
    {
        $log->debug("processing $hostname ...");
        # check if new host exists in the database or not.
        unless ($$db_hoststatus{$hostname})
        {
            # TODO: handle the new host here.
            $log->debug(sprintf 'no known status for %s from the database', $hostname);
            next;
        } elsif ($$db_hoststatus{$hostname}{'state'} != $api_hoststatus{$hostname}{'state'}){
            # TODO: Here we can send a a MSG though GUTTA.
            #   BUT : there will have to be some considerations so that gutta wont send
            #   10000 messages if monitoring 100000 hosts.
            #
        }
        foreach my $service (keys %{$api_servicestatus{$hostname}})
        {
            $log->trace("processing $service for $hostname");
            # check if the service is defined in the database or not.
            unless ($$db_servicestatus{$hostname}{$service})
            {
                # TODO: handle the new service def for new host here.
                $log->debug(sprintf 'no previous service %s for host %s from the database:%s', $service, $hostname, Dumper(%{$$db_servicestatus{$hostname}{$service}}));
                next;
            }

            # get the service state from API and database
            my $api_sstate = $api_servicestatus{$hostname}{$service}{'state'};
            my $db_sstate =  $$db_servicestatus{$hostname}{$service}{'state'};
                                   

            if ($api_sstate != $db_sstate)
            {
                # Here we got a diff between what nagios says and last "known" status (ie what it said last time
                # we checked, that's why this is an event we can send an alarm to or some such)
                #
                $log->debug(sprintf 'service "%s" for host "%s" have changed state from %s to %s.:%s', $service, $hostname, $db_sstate, $api_sstate, $api_servicestatus{$hostname}{$service}{'msg'});

            } else {
                $log->debug(sprintf 'service "%s" for host "%s" remain %i.', $service, $hostname, $db_sstate);
            }
        }

    }


    # OK lets update the database.
    #
    # First remove everyting (almost)!!
=pod
    $sth = $dbh->prepare(qq{
        DELETE FROM monitor_servicedetail
          WHERE NOT host_name IN (SELECT DISTINCT host FROM monitor_hosts)});


     SELECT monitor_hosts_from_hostgroup.hostgroup,
                   monitor_servicedetail.host_name,
                   monitor_servicedetail.service,
                   monitor_servicedetail.state
             FROM  monitor_servicedetail
        INNER JOIN monitor_hosts_from_hostgroup
      ON monitor_hosts_from_hostgroup.host_name = monitor_servicedetail.host_name;



    $sth->execute();
=cut
    $sth = $dbh->prepare(qq{
        REPLACE INTO monitor_servicedetail (
                host_name,
                  service,
                    state,
         has_been_checked) VALUES (?,?,?,?)
     });

    # to update host status.
    $sth2 = $dbh->prepare('UPDATE  monitor_hoststatus SET state = ? where host_name = ?');

    #foreach my $hostname (keys %api_servicestatus)



    # TODO: Fix tomorrow.

    #$sth = $dbh->prepare(qq{
    #    INSERT INTO monitor_servicedetail host_name, service, state, has_been_checked
    #            VALUES (?,?,?,?)});




    return;
}

sub _api_get_host
{
    my $self = shift;
    my $host = shift;
    my %host_services;
    my $hostinfo; # the ref to json if succesful
    # make an API call to the monitor server to fetch info about the host.


    my ($rval, $payload_or_message) = $self->__get_request(sprintf '/status/host/%s', $host);

    if ($rval)
    {
        $hostinfo = from_json(($payload_or_message), { utf8 => 1 });
    } else {
        $log->warn("unable to pull data from $host: $payload_or_message");
        return;
    }

    my $services = @$hostinfo{'services_with_info'};
    $log->trace($services);
    foreach my $service (@$services)
    {
        $log->trace(Dumper($service));
        my ($servicename, $state, $has_been_checked, $msg) = @$service;
        %{$host_services{$servicename}} = (
                   'state' => $state,
                     'msg' => $msg,
               'host_name' => $host,
        'has_been_checked' => $has_been_checked,
        );
        $log->debug(sprintf 'from nagios: service for "%s": "%s" with state %i: "%s"', $host, $servicename, $state, $msg);
    }


    return %host_services;
}


sub _db_get_hosts
{
    my $self = shift;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('SELECT state, host_name FROM monitor_hoststatus');

    $sth->execute();


    my $hosts = $sth->fetchall_hashref('host_name');

    $log->debug(Dumper($hosts));

    return $hosts;
}

sub _db_get_servicestatus
{
    my $self = shift;
    my $dbh = $self->dbh();
    # TODO: Fix this tomorrow.
    my $sth = $dbh->prepare('SELECT state, host_name, has_been_checked, service FROM monitor_servicedetail');

    $sth->execute();


    my $hosts = $sth->fetchall_hashref([ qw/host_name service/ ]);

    $log->debug(Dumper($hosts));

    return $hosts;
}

sub __get_request
{
    my $self = shift;
    # the API path.
    my $path = shift;

    my $password = $self->get_config('password');
    my $username = $self->get_config('username');
    my $nagios_server = $self->get_config('nagios-server');
    my $apiurl = sprintf 'https://%s/api%s?format=json', $nagios_server, $path;

    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $apiurl);

    if ($username && $password)
    {
        $log->info(sprintf 'setting authorization headers username=%s, password=[SECRET]', $username);
        $req->authorization_basic($username, $password);
    }

    # Do the download.
    my $response = $ua->request($req);

    # dome logging
    if ($response->is_success)
    {
        $log->debug("SUCCESSFULLY downloaded $apiurl");
        return 1, $response->decoded_content;
    } else {
        $log->warn(sprintf "ERROR on attempted download of %s:%s", $apiurl, $response->status_line);
        return 0, $response->status_line;
    }
}

sub __insert_new_hoststatus
{
    my $self = shift;
    my $hoststatus = shift;
    my $dbh = $self->dbh();


    my $rc  = $dbh->begin_work;
    
    # cleaning in the database
    my $sth = $dbh->prepare(qq{DELETE FROM monitor_servicedetail});
    $sth->execute();

    # prepairng to insert new stuff.
    $sth  = $dbh->prepare(qq{INSERT OR IGNORE INTO monitor_servicedetail
                            (host_name, service, state, has_been_checked) VALUES(?,?,?,?)});

    while (my ($hostname, $services) = each (%{$hoststatus}))
    {
        while (my ($service, $sd) = each (%{$services}))
        {
            $log->debug("I NOW AM DOING THIS for $hostname - $service `$$sd{msg}`");
            unless($sth->execute($$sd{'host_name'}, $service, $$sd{'state'}, $$sd{'has_been_checked'}))
            {
                $log->warn(sprintf 'Updating monitor_servicedetail failed with msg:"%s". Rolling back.', $dbh->errstr());
                $dbh->rollback;
                last;
            }
        }
    }
    unless ($dbh->commit)
    {
        $log->warn(sprintf 'unable to save new monitor servicedetail:"%s"', $dbh->errstr());
        $dbh->rollback;
    }

}



1;
