package Gutta::Plugin;
use Gutta::DBI;
use Gutta::Context;
use Storable;
use strict;
use warnings;
use DateTime;
use Log::Log4perl;

my $log;

sub new
{
    my $class = shift;
    my $self = bless {
                data => {},
            datafile => undef,
     heartbeat_act_s => 58,   # default act on heartbeats ~ every 58 secs.
    heartbeat_act_ts => time, # Setting timestamp "time is now"
                  db => Gutta::DBI->instance(),
             context => Gutta::Context->new(),
    }, $class;

    $self->__setup_config_shema();
    $self->_initialise();

    return $self;
}

sub process_msg
{
    #  process incoming messages
    my $self = shift;
    return ();
}

sub process_privmsg
{
    #  process incoming messages
    my $self = shift;
    return ();
}

sub _initialise
{
    # called when plugin is istansiated
    my $self = shift;
    #$self->{triggers} = $self->_triggers();
    #$self->{commands} = $self->_commands();

    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",

    # The logger
    $log = Log::Log4perl->get_logger(__PACKAGE__);
}

sub _get_triggers
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    $self->{triggers} ||= $self->_set_triggers();

    return $self->{triggers};
}

sub _get_commands
{
    my $self = shift;
    # override this in plugin to set custom commands
    #
    # The dispatch table for "commands", which is the first word sent to Gutta
    # it may be prefixed with $CMDPREFIX in parent, depending on context:
    #  (private vs public msg)
    #
    return $self->{commands};
}

sub _get_event_handlers
{
    my $self = shift;
    # override this in plugin to set custom event_handlers
    #
    # The dispatch table for "commands", which is the first word sent to Gutta
    # it may be prefixed with $CMDPREFIX in parent, depending on context:
    #  (private vs public msg)
    #
    return $self->{commands};
}

sub _triggers
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.

    return ;
}

sub _commands
{
    my $self = shift;
    # override this in plugin to set custom commands
    #
    # The dispatch table for "commands", which is the first word sent to Gutta
    # it may be prefixed with $CMDPREFIX in parent, depending on context:
    #  (private vs public msg)
    #
    return ;
}

sub load
{
    # load $self->{data} from file
    my $self = shift;
    $self->save() unless -f $self->{datafile};
    $self->{data} = retrieve($self->{datafile});

}

sub save
{
    # save $self->{data} to file
    my $self = shift;
    store \%{$self->{data}}, $self->{datafile};
}

sub heartbeat
{
    # the plugins can handle heartbeats to act upon things outside of the irssi
    my $self = shift;
    my $nowt = time;

    if (($nowt - $self->{heartbeat_act_ts}) >= $self->{heartbeat_act_s})
    {
        $log->trace(sprintf "♥ because %i >= %i", $nowt - $self->{heartbeat_act_ts}, $self->{heartbeat_act_s});
        $self->{heartbeat_act_ts} = $nowt;
        $self->_heartbeat_act;
    }
}

sub _heartbeat_act
{
    # here is acting to the heartbeats. the plugins wanna override
    # this function, but the mechanics for *when* to act
    # pretty much should be the same
    #
    # This is a "void" function. --  Data collected here
    # gets returned by called from heartbeat_res for every connected
    # to server
}

sub heartbeat_res
{
    # Here process irc commands from the plugin from each connected to server
    # The heartbeat sets the date, the result returns it
    my $self = shift;
    my $servername = shift;

    return undef;
}

sub dbh
{
    # Here we supply the database handle for gutta
    #
    my $self = shift;
    return $self->{db}->dbh();
}

sub _dbinit
{
    # DBinit provides support for plugins to initialise their db:s,
    # it runs the sql from the _setup_shema method
    # the $self->setup_shema() class.
    # this can be called multiple times by passing different tables to setup_schema
    my $self = shift;
    my $dbh = $self->dbh();

    foreach my $query ($self->_setup_shema())
    {
        my $sth = $dbh->prepare($query) or die "unable to run: $query\n";
        $sth->execute() or  die "unable to execute; $query\n";
    }
}

sub _setup_shema
{
    my $self = shift;
    my $target_shema = shift;
    #
    # Child Plugins override this method to return the SQL needed to initialise the $target_shema
    # table.
    # It can be arbitrary SQL in here, so use with caution-
    #
    return undef;
}


sub command
{
    my $self = shift;
    my $command = shift;
    # Left in @_ = $server, $msg, $nick, $mask, $target, $rest_of_msg/$pattern_match
    # it will be passed on to the command
    # DO IT (something like this) = shift;
    #
    $self->{commands} ||= $self->_commands();
    return unless $self->{commands};

    return $self->{commands}{$command}->(@_);
}

sub trigger
{
    my $self = shift;
    my $trigger = shift;
    # Left in @_ = $server, $msg, $nick, $mask, $target, $match =  the match in $msg
    # it will be passwed on to the trigger.
    # DO IT (something like this) = shift;
    #
    $self->{triggers} ||= $self->_triggers();
    return unless $self->{triggers};

    
    return $self->{triggers}{$trigger}->(@_);
}

sub handle_event
{
    my $self = shift;
    my $eventtype = shift;
    # Left in 
    # it will
    # DO IT (something like this) = shift;
    #
    $self->{event_handlers} ||= $self->_event_handlers();
    return unless $self->{event_handlers};

    return $self->{event_handlers}{$eventtype}->(@_);
}


#
#  Functions with persistent config
#    in the SQLite database through Gutta::DBI
#
sub __setup_config_shema
{
    #
    # Used to setup a common config table for all plugins.
    # 
    # It's a convenient alternative to storable in the $self->{data},
    # if multiple plugins want to access each others configs.
    # or store simple key value pairs without setting up their own schema
    #
    my $self = shift;
    my $dbh = $self->dbh();

    my $query = qq{
     CREATE TABLE IF NOT EXISTS plugin_config (
      plugin_name TEXT NOT NULL,
              key TEXT NOT NULL,
            value TEXT NOT NULL,
      PRIMARY KEY (plugin_name, key) ON CONFLICT REPLACE

    );};
    my $sth = $dbh->prepare($query) or die "unable to run: $query\n";
    $sth->execute() or  die "unable to execute; $query\n:  $dbh->errstr;";

}

sub set_config
{
    #
    # Set a config in the plugin_config table
    #
    my $self = shift;
    my $dbh = $self->dbh();

    my $key = shift;
    my $value = shift;
    # the name of the calling class.
    my $plugin = shift||scalar caller(0);

    my $sth = $dbh->prepare('INSERT INTO plugin_config (plugin_name,key,value) VALUES(?,?,?)');
    $sth->execute($plugin,$key,$value);

}

sub get_config
{
    #
    # Get a config from the plugin_config table
    #
    my $self = shift;
    my $dbh = $self->dbh();

    my $key = shift;
    my $plugin = shift||scalar caller(0);

    my $sth = $dbh->prepare(qq{SELECT value FROM plugin_config WHERE
                                                               plugin_name=? AND key=? });
    $sth->execute($plugin,$key);

    my ($value) = $sth->fetchrow_array();

    return $value;
}

sub get_all_config
{
    #
    # Get all config values from the plugin_config table
    # for plugin.
    #
    # Return a list of key, value pairs
    #
    my $self = shift;
    my $dbh = $self->dbh();

    my $plugin = shift||scalar caller(0);
    my @values;

    my $sth = $dbh->prepare(qq{SELECT key, value FROM plugin_config WHERE plugin_name=?});
    $sth->execute($plugin);

    while (my ($key, $value) = $sth->fetchrow_array())
    {
        push @values, [ $key, $value ];

    }

    return @values;
}

1;
