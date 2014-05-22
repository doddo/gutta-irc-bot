package Gutta::Plugins::Nagios;
# does something with Nagios

use parent Gutta::Plugin;
use Gutta::Color;

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

=head1 monitor

Monitor has a lot of subsections, such like "config", "hostgroup", "host", "hostgroupstatus" and "status".

=head2 config

Used like this:

 '!monitor config [ --username NAGIOSUSERNAME ] [ --password PASSWORD  ] [ --nagios-server HOSTNAME ] [ --prefix PREFIX ]

for example say this:

 '!monitor config --username monitor --password monitor --nagios-server 192.168.60.182' --prefix ALARM

to configure a connection to monitor at 192.168.60.182 using username monitor and password monitor. All alarms originating will be prefixed with "ALARM".

=head2 hostgroup

!monitor hostgroup unix-servers --irc-server .* --to-channel #test123123

To add op5 irc monitoring for all servers in the unix-servers hostgroups on all servers, and send messages Crit, Warns and Clears to channel #test123123

=head2 hostgroupstatus

Get status summary from the hostgroups configured in originating #channel.

!monitor hostgroupstatus

=head2 filter

Sometimes the Nagios your connecting to sends a lot of bad alarms. Although it should be fixed in the nagios itself, gutta the bot can filter
these messages with the add/del commands.

 !monitor filter [ add FILTER | del FILTER | list ]

=head3 add

To add a filter which should never be sent to channel, do

 !monitor filter add [regex to filter out]

=head3 del

To delete the filter, do this:

 !monitor filter del [regex to remvoe]

=head3 list

To see what is filtered, do a

 !monitor filter list


=head1 unmonitor

unmonitor a lot of monitored things

!unmonitor hostgroup HOSTGROUP

=head2 hostgroup

unmonitor hostgroup allows you to unmonitor the hostgroups.

!unmonitor hostgroup unix-servers

will remove the monitoring for unix-servers hostgroup, if such monitoring was configured.


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



    # How often to act? I think best if there are like 5-10 min inbetween
    # Atleast.
    #
    # Anyways, this is configurable, but will default to ~ 6.7 min.
    #  you do it witn !monitor config --check-interval 500
    #  (for 500 seconds)
    $self->{heartbeat_act_s} = $self->get_config('check-interval')||406;   #  act on heartbeats ~ every 6.7 min.
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
              state INTEGER NOT NULL,
        is_flapping INTEGER DEFAULT 0,
      plugin_output TEXT,
          timestamp INTEGER DEFAULT 0
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_servicedetail (
          host_name TEXT NOT NULL,
            service TEXT NOT NULL,
              state INTEGER DEFAULT 0,
        is_flapping INTEGER DEFAULT 0,
      plugin_output TEXT,
   has_been_checked INTEGER DEFAULT 0,
          timestamp INTEGER DEFAULT 0,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name),
      CONSTRAINT uniq_service UNIQUE (host_name, service)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_hosts_from_hostgroup (
          host_name TEXT NOT NULL,
          hostgroup TEXT NOT NULL,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name),
    FOREIGN KEY (hostgroup) REFERENCES monitor_hostgroups(hostgroup),
      CONSTRAINT uniq_hgconf UNIQUE (host_name, hostgroup)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_message_hosts (
          host_name TEXT PRIMARY KEY,
          old_state INTEGER,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_message_servicedetail (
          host_name TEXT NOT NULL,
            service TEXT NOT NULL,
          old_state INTEGER,
    FOREIGN KEY (host_name) REFERENCES monitor_hoststatus(host_name),
    FOREIGN KEY (service) REFERENCES monitor_servicedetail(service),
      CONSTRAINT uniq_service_per_host UNIQUE (host_name, service)
    )}, qq{
    CREATE TABLE IF NOT EXISTS monitor_filters (
             filter TEXT PRIMARY KEY
    )}, qq{
    CREATE VIEW IF NOT EXISTS monitor_hostgroupstatus AS
            SELECT a.hostgroup,
                   a.host_name,
                   b.state,
                   c.services_with_error
              FROM monitor_hosts_from_hostgroup a
        INNER JOIN monitor_hoststatus b
                ON a.host_name = b.host_name
         LEFT JOIN (
                            SELECT host_name,
                   COUNT(state) AS services_with_error
                              FROM monitor_servicedetail
                             WHERE state > 0
                          GROUP BY host_name
                    ) c
                ON c.host_name = b.host_name
       });

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
        case        'hostgroup' { @irc_cmds = $self->_monitor_hostgroup(@values) }
        case           'config' { @irc_cmds = $self->_monitor_config(@values) }
        case             'dump' { @irc_cmds = $self->_monitor_login(@values) }
        case          'runonce' { @irc_cmds = $self->_monitor_runonce(@values) }
        case           'filter' { @irc_cmds = $self->_monitor_filter(@values) }
        case       'hoststatus' { @irc_cmds = $self->_monitor_hoststatus(@values) }
        case  'hostgroupstatus' { @irc_cmds = $self->_monitor_hostgroupstatus($target, @values) }
        case 'hostgroupdetails' { @irc_cmds = $self->_monitor_hostgroupdetails($target, @values) }
        case            'satus' { @irc_cmds = $self->_monitor_status(@values) }
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

    # the PRIVMSG to return.
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
             'prefix=s',
      'nagios-server=s',
    ) or return "invalid options supplied:";

    while(my ($key, $value) = each %config)
    {
        $log->info("setting $key to $value for " . __PACKAGE__ . ".");
        $self->set_config($key, $value);
    }
    
   # ONE TIME DO THIS (special case for handling global config):
   $self->{heartbeat_act_s} = $config{'check-interval'} if $config{'check-interval'};


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

    # Return gets put into here after suffixing.
    my @irc_cmds;

    # they need subcmd.
    return "need more info. (try help unmonitor)" unless $rest_of_msg;

    # Cmd can look like this: !unmonitor hostgroup unix-servers
    # in which case rest of msg looks like this: hostgroup unix-server
    
    # get the commands.
    my ($subcmd, @values) = split(/\s+/, $rest_of_msg);

    switch (lc($subcmd))
    {
        case 'hostgroup' { @irc_cmds = $self->_unmonitor_hostgroup(@values) }
    }

    return map { sprintf 'msg %s %s: %s', $target, $nick, $_ } @irc_cmds;

}

sub _unmonitor_hostgroup
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
    my $sth = $dbh->prepare(qq{
            DELETE FROM monitor_hostgroups
                  WHERE hostgroup = ?
                    AND irc_server = ?
                    AND channel = ?}) or return $dbh->errstr;

    # And DO it.
    $sth->execute($hostgroup, $server, $channel) or return $dbh->errstr;

    # the PRIVMSG to return.
    return "OK - I think I just removed monitoring for hostgroup:[$hostgroup] on channel:[$channel] for servers matching re:[$server]";
}


sub _monitor_hoststatus
{
    my $self = shift;

    # TODO:
    # Check if data is up to date (or call _monitor_runconce)
    # Return data for host if specified,
    # or an executive summary.


    return "here will be status for each host...";
}

sub _monitor_status
{
    my $self = shift;

    # TODO:
    # Check if data is up to date (or call _monitor_runconce)
    # Return data for hostgroup if specified,
    # or an executive summary.


    return "here will be status for each hostgroup...";
}

sub _monitor_hostgroupstatus
{
    # will summarize the configured hostgroups for the channel
    # from which the request originated and send back an executive summary.
    my $self = shift;
    my $target = shift;

    my @responses;

    # first check is to see if the request came from a channel.
    if (substr($target, 0, 1) eq '#')
    {
        # first char was a #, so target is a channel.

        #
        my $dbh = $self->dbh();
        my $nagios_server = $self->get_config('nagios-server');

#https://192.168.60.182/monitor/index.php/listview?q=[hosts]\%20in\%20\%22unix-servers\%22
        my $sth = $dbh->prepare(qq{
                              select a.hostgroup,
                    count(host_name) total_hosts,
                          sum(state) hosts_with_error,
            sum(services_with_error) services_with_error_total
                                from monitor_hostgroupstatus a
                          inner join monitor_hostgroups b
                                  on a.hostgroup = b.hostgroup
                               where channel = ?
                            group by a.hostgroup
        });

        $sth->execute($target);


        # OK create the responses.
        while(my ($hostgroup, $total_hosts, $hosts_with_error, $services_with_error_total) = $sth->fetchrow_array())
        {
            push @responses, sprintf '%12s have %3i hosts. %2i of the hosts are down. there are %3i services with error. https://%s/monitor/index.php/listview?q=[hosts]%%20in%%20%%22%s%%22',
                      $hostgroup, $total_hosts, $hosts_with_error, $services_with_error_total, $nagios_server, $hostgroup;
        }

    } else {
        # target was not a channel, but a nick maybe.
        # what shall be replied? i don't know. (it depends, maybe add some logic to pass optional value for hostgroup to check or something

        push @responses ,'hostgroupstatus works best if run from a channel with nagios hostgroup associated with it.';
    }
    

    return @responses;
}

sub _monitor_hostgroupdetails
{
    # will summarize the configured hostgroups for the channel
    # from which the request originated and send back an executive summary.
    my $self = shift;
    my $target = shift;

    my $nagios_server = $self->get_config('nagios-server');

    my @responses;

    # first check is to see if the request came from a channel.
    if (substr($target, 0, 1) eq '#')
    {
        # first char was a #, so target is a channel.

        #
        my $dbh = $self->dbh();

        my $sth = $dbh->prepare(qq{
                              SELECT host_name,
                                     state,
                                     services_with_error
                                FROM monitor_hostgroupstatus a
                          INNER JOIN monitor_hostgroups b
                                  ON a.hostgroup = b.hostgroup
                               WHERE channel = ?
                            GROUP BY host_name
        });

        $sth->execute($target);
        
        while(my ($host_name, $state, $services_with_error) = $sth->fetchrow_array())
        {
            push @responses, sprintf '%-8s is: %-7s (It has %2i services with error). http://%s/monitor/index.php/extinfo/details/host/%s',
                   $host_name, $self->__translate_return_codes($state, 'host'), $services_with_error, $nagios_server, $host_name;
        }

    } else {
        # target was not a channel, but a nick maybe.
        # what shall be replied? i don't know.

        push @responses ,'hostgroupdetails works best if run from a channel with nagios hostgroup associated with it.';
    }

    return @responses;
}



sub _monitor_runonce
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


    $log->trace("DB_SERVICESTATUS:" . Dumper($db_servicestatus));

    # now remove the hostgroups from the monitor_hosts_from_hostgroup, it will need new hosts now.
    my $sth2 = $dbh->prepare('DELETE FROM monitor_hosts_from_hostgroup');
    $sth2->execute();

    # prepare a new statement to re-populate that hostgroup...
    $sth2 = $dbh->prepare('INSERT OR IGNORE INTO monitor_hosts_from_hostgroup (host_name, hostgroup) VALUES (?,?)');

    # Prepare to add a new host into monitor_hoststatus
    my $sth3 = $dbh->prepare('INSERT OR REPLACE INTO monitor_hoststatus (host_name, state, plugin_output, timestamp) VALUES(?,?,?,?)');

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
            my $timestamp = time;

            my $members = @$payload{'members_with_state'};

            foreach my $member (@$members)
            {
                my ($hostname, $state, $has_been_checked) = @$member;

                $log->debug(sprintf 'got %s with state %i. been checked=%i', $hostname, $state, $has_been_checked);
                # GET servicestatus AND some "valuable" info from the monitor API
                (my $plugin_output, my $is_flapping, %{$api_servicestatus{$hostname}}) = $self->_api_get_host($hostname);

                # create the hoststatus hash to look the same as what we got from the db earlier (hopefully)
                %{$api_hoststatus{$hostname}} = (
                               state => $state,
                    has_been_checked => $has_been_checked,
                       plugin_output => $plugin_output,
                         is_flapping => $is_flapping
                );


                $log->trace(Dumper(%{$api_hoststatus{$hostname}}));

                # Add to monitor_hosts_from_hostgroup (so we know what hostgroups this host belong to
                $sth2->execute($hostname, $hostgroup);
                # And insert the state of the host here.
                $sth3->execute($hostname, $state, $plugin_output, $timestamp);

            }
        }
    }


    # Insert the host status stuff into the database...
    $self->__insert_new_servicestatus(\%api_servicestatus);


    # OK so lets compare few things.
    foreach my $hostname (keys %api_servicestatus)
    {
        $log->debug("processing $hostname ...");
        $log->trace(Dumper($api_hoststatus{$hostname}));

        # save these here so as to not have to type so much.
        my $api_hoststate = $api_hoststatus{$hostname}{'state'};
        my $api_is_flapping = $api_hoststatus{$hostname}{'is_flapping'};

        # check if new host exists in the database or not.
        unless ($$db_hoststatus{$hostname})
        {
            # A host not known of before pops up. What do we do with it?
            $log->info(sprintf 'New host?: No known status for %s from the database.', $hostname);

            # Answer: First, we chek whazzup with the host, is it down? then lets message.
            if ($api_hoststatus{$hostname}{'state'} != 0)  #TODO sometimes 1 is OK
            {
                # add it with previous status 3=DOWN/UNREACHABLE.
                #         (http://nagios.sourceforge.net/docs/3_0/pluginapi.html)
                $self->__insert_hosts_to_msg([$hostname, 3 ]);
            }
        } elsif ((($$db_hoststatus{$hostname}{'state'} != $api_hoststate) && $api_is_flapping == 0) ||
                             ($api_is_flapping != $$db_hoststatus{$hostname}{'is_flapping'})) {
            # HOST STATUS CHANGE HERE.
            # This is important, because if a host is down, we dont want to send the alarms for that host.
            $log->debug(Dumper($api_hoststatus{$hostname}));
            $self->__insert_hosts_to_msg([$hostname, $$db_hoststatus{$hostname}{'state'}]);
        }
        #
        #   Here comes the service checks, but we're only interrested in those
        #   if the host itself is up, because if host is down, everything will alarm.
        #
        if ($api_hoststatus{$hostname}{'state'} == 0)
        {
            #   Check all services
            foreach my $service (keys %{$api_servicestatus{$hostname}})
            {
                $log->trace("processing $service for $hostname");
                # check if the service is defined in the database or not.
                unless ($$db_servicestatus{$hostname}{$service})
                {
                    # Handle the new service def for new host here.
                    if ($api_servicestatus{$hostname}{$service}{'state'} != 0)
                    {
                        # add it with previous status 3=UNKNOWN
                        #         (http://nagios.sourceforge.net/docs/3_0/pluginapi.html)
                        $self->__insert_services_to_msg([$hostname,$service, 3]);
                    }

                    $log->debug(sprintf 'no previous service %s for host %s from the database.', $service, $hostname);
                    next;
                }

                #
                # get the service state from API and database and whether it's flapping or not.
                # We dont wanna spoam with flapping services.
                #
                my $api_sstate   = $api_servicestatus{$hostname}{$service}{'state'};
                my $db_sstate    = $$db_servicestatus{$hostname}{$service}{'state'};
                my $api_flapping = $api_servicestatus{$hostname}{$service}{'is_flapping'};
                my $db_flapping  = $$db_servicestatus{$hostname}{$service}{'is_flapping'};

                $log->trace( Dumper($$db_servicestatus{$hostname}{$service}) );

                if ((($api_sstate != $db_sstate) && $api_flapping == 0) || ($db_flapping != $api_flapping))
                {
                    #
                    # Here we got a diff between what nagios says and last "known" status (ie what it said last time
                    # we checked, that's why this is an event we can send an alarm to or some such)
                    # And its not flapping.
                    #
                    #  OR otherwise service have either started or stopped flapping.
                    #
                    $log->debug(sprintf 'service "%s" for host "%s" have changed state from %s to %s.:%s', $service, $hostname, $db_sstate, $api_sstate, $api_servicestatus{$hostname}{$service}{'plugin_output'});

                    # Prepare tha database for the new message about what's changed.
                    $self->__insert_services_to_msg([$hostname, $service, $db_sstate]);

                } else {
                    $log->debug(sprintf 'service "%s" for host "%s" remain %i.', $service, $hostname, $db_sstate);
                }
            }
        }
    }

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

    # Get all the services
    foreach my $service (@$services)
    {
        $log->trace(Dumper($service));
        my ($servicename, $state, $has_been_checked, $plugin_output) = @$service;
        %{$host_services{$servicename}} = (
                   'state' => $state,
           'plugin_output' => $plugin_output,
               'host_name' => $host,
        'has_been_checked' => $has_been_checked,
             'is_flapping' => 0, # TODO fix, requires extra api call.
        );
        $log->trace(sprintf 'from nagios: service for "%s": "%s" with state %i: "%s"', $host, $servicename, $state, $plugin_output);
    }

    # status message in human readable format.
    my $plugin_output = $$hostinfo{'plugin_output'};
    my $is_flapping   = $$hostinfo{'is_flapping'};

    return $plugin_output, $is_flapping, %host_services;
}


sub _db_get_hosts
{
    my $self = shift;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('SELECT state, is_flapping, host_name FROM monitor_hoststatus');

    $sth->execute();


    my $hosts = $sth->fetchall_hashref('host_name');

    $log->trace(Dumper($hosts));

    return $hosts;
}

sub _db_get_servicestatus
{
    my $self = shift;
    my $dbh = $self->dbh();
    # Here the last known statuses are fetched from the database !!
    my $sth = $dbh->prepare('SELECT state,
                                    host_name,
                                    has_been_checked,
                                    service,
                                    is_flapping
                               FROM monitor_servicedetail');

    $sth->execute();


    my $hosts = $sth->fetchall_hashref([ qw/host_name service/ ]);

    $log->trace(Dumper($hosts));

    return $hosts;
}

sub _monitor_filter
{
    my $self = shift;
    # THE FUNCTION TO HANDLE FILTERS!!!
    # this is ugly code so putting it in the middle of the program
    # so ppl wqont see it so easy...
    my $action = shift;
    my $regex = join(' ',@_);

    my $dbh = $self->dbh();
    $action||='list';
    my @responses;

    if ($action eq 'add')
    {
        return "not specific enouyh regex" unless $regex;
        my $sth = $dbh->prepare('INSERT INTO monitor_filters (filter) VALUES(?)');
        $sth->execute($regex) or return "Got error:" .  $dbh->errstr();
        return "OK added filter [$regex]\n";
    } elsif ($action eq 'del') {
        return "not specific enouyh regex" unless $regex;
        my $sth = $dbh->prepare('DELETE FROM monitor_filters where filter = ?');
        $sth->execute($regex) or return "Got error:" .  $dbh->errstr();
        return "OK deleted.";
    } else {
        my $sth = $dbh->prepare('SELECT filter FROM monitor_filters');
        $sth->execute();
        # TODO: a message if there are 0 rows selected.
        while (my ($filter) = $sth->fetchrow_array())
        {
            push (@responses, "this is a filter:'$filter'");
        }
        return @responses;
   }
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

sub __insert_new_servicestatus
{
    my $self = shift;
    my $hoststatus = shift;
    my $dbh = $self->dbh();


    my $rc  = $dbh->begin_work;

    # timestamp

    my $timestamp = time;

    # prepairng to insert new stuff.
    my $sth  = $dbh->prepare(qq{INSERT OR REPLACE INTO monitor_servicedetail
                                                     ( host_name,
                                                       service,
                                                       plugin_output,
                                                       state,
                                                       is_flapping,
                                                       has_been_checked,
                                                       timestamp )
                                              VALUES (?,?,?,?,?,?,?)});

    while (my ($hostname, $services) = each (%{$hoststatus}))
    {
        while (my ($service, $sd) = each (%{$services}))
        {
            $log->trace("I NOW AM DOING THIS for $hostname - $service `$$sd{plugin_output}`");
            unless($sth->execute($$sd{'host_name'}, $service, $$sd{'plugin_output'}, $$sd{'state'}, $$sd{'is_flapping'}, $$sd{'has_been_checked'}, $timestamp))
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
        $dbh->rollback or $log->warn("unable to roll back the changes in the db:" . $dbh->errstr());
    }
}

sub __insert_hosts_to_msg
{
    # insert a few rows to this table, and then gutta the bot knows what to msg in the channels about when the time comes.
    # here are specific things for the HOSTS which gutta monitors.
    my $self = shift;
    my @hosts_to_msg = @_;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('INSERT OR REPLACE INTO monitor_message_hosts (host_name, old_state) VALUES(?,?)');

    foreach my $what2add (@hosts_to_msg)
    {
        my ($host_name, $old_state) = @{$what2add};
        $sth->execute($host_name, $old_state);
    }
}

sub __insert_services_to_msg
{
    # insert a few rows to this table, and then gutta the bot knows what to msg in the channels about when the time comes.
    # here are specific things for the HOSTS services to monitor about.
    my $self = shift;
    my @hosts_to_msg = @_;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('INSERT OR REPLACE INTO monitor_message_servicedetail
                                        (host_name, service, old_state) VALUES(?,?,?)');

    foreach my $what2add (@hosts_to_msg)
    {
        my ($host_name, $service, $old_state) = @{$what2add};
        $sth->execute($host_name, $service, $old_state);
    }
}

sub _heartbeat_act
{
    #  Gets called when the heartbeat is time to act.
    #
    #


    my $self = shift;
    $self->_monitor_runonce;
}

sub heartbeat_res
{
    # heartbeat res gets called on regular basis ~2sek interval.
    # the response gets populated if anything new is found, and then it
    # is sent to the server.
    my $self = shift;
    my $server = shift;

    my $dbh = $self->dbh();
    my $sth;

    # The responses to return from this sub.
    # It's a flat list of IRC PRIVMSGS
    my @responses;

    # timestamp
    my $timestamp = time; # TODO add timestamp to filter out "stale" alarms (it easy)

    my $msgprefix = $self->get_config('prefix') || 'Nagios';


    # Here is the check for the HOST statuses, by querying the "monitor_message_host"
    # table to check if a new message's popped up.
    $sth = $dbh->prepare(qq{
          SELECT a.host_name,
                 b.plugin_output,
                 b.state
            FROM monitor_message_hosts a
      INNER JOIN monitor_hoststatus b
              ON a.host_name = b.host_name
      INNER JOIN monitor_hosts_from_hostgroup c
              on c.host_name = a.host_name
    });

    $sth->execute();
    my $hoststatus = $sth->fetchall_hashref([qw/host_name/]);

    # Here is to check for the hosts SERVICE statuses, by querying the
    # "monitor_message_servicedetail" table to check if a new message's popped up.
    $sth = $dbh->prepare(qq{
         SELECT a.host_name,
                b.service,
                b.plugin_output,
                b.state,
                b.timestamp
           FROM monitor_message_servicedetail a
     INNER JOIN monitor_servicedetail b
             ON a.host_name = b.host_name
            AND a.service = b.service
     INNER JOIN monitor_hosts_from_hostgroup c
             ON a.host_name = c.host_name
          WHERE a.host_name
         NOT IN ( SELECT host_name
                    FROM monitor_hoststatus
                   WHERE state != 0 )
    });

    $sth->execute();
    my $services = $sth->fetchall_hashref([ qw/host_name service/ ] );

    # Return if no messages have been found. This is what will happen most of the
    # time considering how often this table gets queried.
    unless (%{ $services } or  %{ $hoststatus })
    {
        $log->trace('Nothing to report.');
        return;
    }

    # Here's to check who to send what to  (what channels on which servers etc)
    $sth  = $dbh->prepare(qq{
      SELECT DISTINCT irc_server, channel, host_name
        FROM  (SELECT irc_server, channel, host_name
                FROM monitor_hosts_from_hostgroup a
          INNER JOIN monitor_hostgroups b
                  ON a.hostgroup = b.hostgroup)
    });

    $sth->execute();
    my $servchan = $sth->fetchall_hashref([ qw/irc_server channel host_name/ ]);


    # A little traceging for troubleshooting.
    $log->trace("  SERVCHAN:" . Dumper($servchan));
    $log->trace("HOSTSTATUS:" . Dumper($hoststatus));
    $log->trace("  SERVICES:" . Dumper($services));

    # List all the servers and chan config
    while (my ($server_re, $chan) = each (%{$servchan}))
    {
        # step 1. is filtering out what server is coming and see what is relevant
        if ($server =~ qr/$server_re/)
        {
            # server match found here. so continuing exploring.
            $log->info("'$server' matches regex '$server_re': Proceeding.");

            # extract all the channels to queue IRC messages responses here.
            while (my ($channel, $hosts) = each (%{$chan}))
            {
                while (my ($host_name, $host_msg_cfg) = each (%{$hosts}))
                {
                    $log->debug("evaluating $$host_msg_cfg{'host_name'}");
                    # First: a check here to see what's up with the HOSTS
                    # TODO: a check here to see if joined to chan
                    #(no supprort for that yet thoough)
                    if ($$hoststatus{$$host_msg_cfg{'host_name'}})
                    {
                        # TODO: here can check if keys %{chan} > X to determine if something is *really* messed up
                        # and write something about that, because there's a risk of flooding if sending too many PRIVMSGS.
                        # and if 20+ hosts are down or uå, you can bundle the names and say THESE ARE DOWN (list of hosts)
                        # and these hosts are UP (list of hosts)

                        # First take relevant info here so as to not have to type so much.
                        my $s = $$hoststatus{$$host_msg_cfg{'host_name'}};
                        $log->debug("Will send a message about $$host_msg_cfg{'host_name'} to $channel, saying  this: " . Dumper($s));
                        # Format a nicely formatted message here.
                        push @responses, sprintf 'msg %s %s %s: "%s": %s', $channel, $msgprefix, $self->__translate_return_codes($$s{'state'},'host'), $$s{'host_name'}, $$s{'plugin_output'};
                    } elsif ($$services{$$host_msg_cfg{'host_name'}}) {
                        # TODO: here can check if keys %{chan} > X to determine if something is *really* messed up
                        # and write something about that, because there's a risk of flooding if sending too many PRIVMSGS.
                        # and if 20+ services are down, you can bundle the names and say THESE HOSTS ARE X (list of hosts)

                        # First take relevant info here so as to not have to type so much.
                        my $s = $$services{$$host_msg_cfg{'host_name'}};

                        $log->trace("Will send a message about $$host_msg_cfg{'host_name'} to $channel, saying  this: " . Dumper($s));
                        while (my ($service_name, $service_data) = each (%{$s}))
                        {
                            if ($self->__passes_filter($service_name))
                            {
                                $log->debug("Will I send a message about $$host_msg_cfg{'host_name'} service $service_name to $channel, saying  this: " . Dumper($service_data));
                                push @responses, sprintf 'msg %s %s %s: %s "%s": %s', $channel, $msgprefix, $self->__translate_return_codes($$service_data{'state'}), $$host_msg_cfg{'host_name'}, $service_name, $$service_data{'plugin_output'};
                            }
                        }
                    }
                }
            }
        } else {
            $log->info("$server DOES NOT match regex $server_re: Skipping.");

        }
    }

    #
    # OK removing the junk from the db, I dont think this is thread safe
    #
    $sth = $dbh->prepare('DELETE FROM monitor_message_servicedetail');
    $sth->execute;
    $sth = $dbh->prepare('DELETE FROM monitor_message_hosts');
    $sth->execute;

    return @responses;
}

sub __translate_return_codes:
{
    # translates responsecodes from the integers returned from plugins:
    #       http://nagios.sourceforge.net/docs/3_0/plugins.html
    # to their textual representations.
    #
    # Also add some colors :)
    my $self = shift;
    #  Plugin Return Code  Service State   Host State
    #  0                   OK              UP
    #  1                   WARNING         UP or DOWN/UNREACHABLE*
    #  2                   CRITICAL        DOWN/UNREACHABLE
    #  3                   UNKNOWN         DOWN/UNREACHABLE
    #
    # *  Note: If the use_aggressive_host_checking option is enabled,
    #    return codes of 1 will result in a host state of DOWN or UNREACHABLE.
    #    Otherwise return codes of 1 will result in a host state of UP.

    my $return_code = shift;
    my $service_or_host = shift||'service';

    my $what;

    my @colors = ( $Gutta::Color::Green,
                   $Gutta::Color::Orange,
                   $Gutta::Color::LightRed,
                   $Gutta::Color::LightRed );

    my @host_states = ( 'UP',
                        'DOWN', # TODO FIX
                        'DOWN',
                        'DOWN');
    my @service_states = qw/OK WARNING CRITICAL UNKNOWN/;


    if ($service_or_host eq 'service')
    {
        $what = \@service_states;
    } elsif ($service_or_host eq 'host') {
        $what = \@host_states;
    } else {
        # HERE A PROGRAMMING ERROR IS FOUND
        $log->warn("$service_or_host is neither 'service' nor 'host'")
    }

    return $colors[$return_code] . $$what[$return_code] . $Gutta::Color::Reset;

}

sub __passes_filter
{
    my $self = shift;
    # With the list of filters from filters list, check if something matches
    # and return it.
    my $service_to_check = shift;

    my $dbh = $self->dbh();
    my $sth = $dbh->prepare('SELECT filter FROM monitor_filters');
    $sth->execute();

    while (my ($filter) = $sth->fetchrow_array())
    {
        if ($service_to_check =~ m/$filter/)
        {
            # OK returning what filter matched.
            $log->debug("Filtered output about '$service_to_check'. (caught in filter:'$filter')");
            return 0;
        }
    }

    # OK PASSED FILTER
    return 1;
}

1;
