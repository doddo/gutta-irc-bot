package Gutta::Plugins::Jira;
# does something with Jira

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

my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head1 NAME

Gutta::Plugins::Jira


=head1 SYNOPSIS

Provides Jira connection to gutta bot


=head1 DESCRIPTION

Can do a multitude of things.

1. you need to set login credentials (if required)

This is done by chatting with the bot in a channel

you say !jira set username=<username>
then !jira set password=<password>

then you set the url (hostname of your jira installation)
!jira set url <jira.atlassian.example.com>

now if you mention something which looks like jira ticket in chat,
bot will try to resolv into description and say the title and url in the chat.

Also, you can configure a feed. The feed will let bot monitor jira Atom feed,
and will chat in a preset list of channels and servers about what it found

it configureis like this:

say this:
!jira feed add CONF --server .* --channel #test123123'

there can be a lot of --server and --channel flags in the same command line.

then using the heartbeat, it will act on timer and poll on regular basis.

=head1 jira

Configure the configurations of jira. 

use "jira set" to configure the jira server connection and other settings

use "jira feed"  to configure feeds.

=head2 set

To set the hostname of the jira server you want to connect:

  !jira set url=<jiraserver>

To configure username (if needed) you say 

  !jira set username=<username>

To configure password (if needed) you say 

  !jira set password=<password>


=head1 feed

Used like this:

 !jira feed [add | del] [ FEEDKEY ] --server [ SERVER ] --channel [ CHANNEL ] '

=over 8

=item B<--server>

regex to match for irc server connected to.

=item B<--channel>

To what IRC channel do we send these messages?

=back

=cut


sub process_msg
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
 
    return undef unless $msg;
    if ($rest_of_msg =~ /set (username|password|url)=(\S+)\b/ ) {
        $self->set_config($1, $2);
        return sprintf "msg %s %s: OK - [%s] set to [%s]", $target, $nick, $1, $self->get_config($1);
    } elsif ($rest_of_msg =~ /^feed/){
        return "msg ${target} " . $self->__setup_jira_feed(split(/\s+/,$rest_of_msg));
    } elsif ($rest_of_msg =~ /^Dump/i ) {
        # TODO: fix this
        warn Dumper($self->{data});
        return "msg $target $nick: dumped config to log for now...\n";
    } elsif ($rest_of_msg =~ /^i(?:'m| ?am)\s+(\S+)\b/i ) {
        $self->set_jira_user($nick, $1);
        my $jira_user_name = $self->get_jira_user($nick);
        return "msg $target $nick: OK -  you are '$jira_user_name'"
    } elsif ($rest_of_msg =~ /who\s*am\s*i/i ) {
        my $jira_user_name = $self->get_jira_user($nick);
        if ($jira_user_name)
        {
            return "msg $target $nick: you are '$jira_user_name'.\n";
        } else {

            return "msg $target $nick: I don't know who you are.";
        }
     } else {
        return "msg $target $nick: Illegal command '$rest_of_msg'. (Help not implemented yet).";
    }
}

sub _initialise
{
    my $self = shift;
    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",
    # this plugin NEEDS a thread of its own.
    $self->{want_own_thread} = 1;
    $self->_dbinit(); #setup jira database tables
    $self->load(); # load the jira file
}

sub _triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;

    return {
        qr/[A-Z]{3,30}-[0-9]++(?!:)/ => sub { $self->get_jira_issue(@_) },
    };
}


sub _commands
{
    # The commands for JIRA plugin.
    my $self = shift;

    return {
        'jira' => sub { $self->process_msg(@_) },
    };
}


sub _setup_shema
{
    my $self = shift;

    my @queries  = (qq{
    CREATE TABLE IF NOT EXISTS jira_feeds (
            feedkey TEXT NOT NULL PRIMARY KEY,
         last_check INTEGER DEFAULT 0
    )}, qq{
    CREATE TABLE IF NOT EXISTS jira_feeds_channels (
            feedkey TEXT NOT NULL,
            channel TEXT NOT NULL,
             server TEXT NOT NULL,
             filter TEXT,
      FOREIGN KEY (feedkey) REFERENCES jira_feeds(feedkey) ON DELETE CASCADE,
      CONSTRAINT onefc UNIQUE (feedkey, channel, server)
    )}, qq{
    CREATE TABLE IF NOT EXISTS jira_users (
              nick TEXT PRIMARY KEY,
     jira_username TEXT NOT NULL,
      FOREIGN KEY (nick) REFERENCES users(nick) ON DELETE CASCADE
    )});

    return @queries;

}
sub __setup_jira_feed
{
    # the command line interface
    # for configuring feeds
    # it is a little ugly but will be fixed sometime
    my $self = shift;
    shift; #feed
    my $action = shift;
    my $feedkey = shift;
    my @args = @_;
    my $feed;
        print $action . "\n";

    if ($action eq 'del')
    {
        delete($self->{data}{feeds}{$feedkey});
        $self->save();
        return "undefined feed $feedkey";
    } elsif($action eq 'list') {
        return Dumper($self->{data}{feeds});
    } elsif($action eq 'add') {
        undef($self->{data}{feeds}{$feedkey});
        $feed = \%{$self->{data}{feeds}{$feedkey}};
    } elsif ($action eq 'test') {
        my ($status, $feeddata) = $self->__download_jira_feed($feedkey);
        if ($status)
        {
            return "OK: $status";
        } else {
            return "NOT OK: $feeddata";
        }
    }

    my $ret = GetOptionsFromArray(\@args, $feed,
        'server=s@',
        'channel=s@'
    ) or return "invalid options supplied.";

    $self->save();
    return sprintf ("adding feed '%s' servers '%s' and channels '%s'",
                   $feedkey, join(',', @{$$feed{server}}), join(',', @{$$feed{channel}}));
}

sub _heartbeat_act
{
    my $self = shift;
    if (scalar keys %{$self->{data}{feeds}} >0)
    {
        warn "calling monitor_jira_feed\n";
        $self->monitor_jira_feed;
    }
}

sub heartbeat_res
{
    # the response gets populated if anything new is found, and then it
    # is sent to the server.
    my $self = shift;
    my $server = shift;
    my $news = $self->{news};
    my $server_ok = 0;
    my @payload;
    foreach my $feedkey (keys %{$news})
    {
        # OK check if the feed is configured for this server.
        foreach my $server_ok_re  (@{$self->{data}{feeds}{$feedkey}{server}})
        {
            if ($server =~ $server_ok_re)
            {
                $log->debug("$server matched $server_ok_re. Good.");
                $server_ok = 1;
            }
        }
        # OK - lets return here if no server mathced
        return unless $server_ok;
        
        while (my $news_item = shift @{$$news{$feedkey}})
        {
            # OK check which channels to push these intresting news to
            foreach my $channel (@{$self->{data}{feeds}{$feedkey}{channel}})
            {
                # build the pure irc command here, and push into the @payload.
                push @payload, "msg ${channel} " . $news_item;
            }
        }
    }
    delete($self->{news});
    return @payload
}

sub monitor_jira_feed
{
    # Downloads and parses the configured feeds (if any)
    # Updates timestamp for those feeds too if activity founds
    # and populates the heartbeat_res with a bunch of responses.
    #
    my $self = shift;
    my $feeds = \%{$self->{data}{feeds}};
    my $hs = HTML::Strip->new();
    my $strp = DateTime::Format::Strptime->new(
        pattern   => "%Y-%m-%dT%H:%M:%S%Z",
        on_error  => 'croak',
    );
    my %news;
    $self->{news} = \%news;
    my %latest_timestamp;
    my $nowt = DateTime->now();
    
    # Download ALL the keys in one go.
    my ($status, $feeddata) = $self->__download_jira_feed(keys %{$feeds});
    unless ($status)
    {
       $log->error("unable to download jira feeds...: $feeddata\n");
       return;
    }
 
    # Parse the feeddata
    my $feed = XML::FeedPP->new($feeddata);
    
    foreach my $item ($feed->get_item())
    {
        my $title = $item->title();
        
        # parse the pubDate from the item (the news item)
        my $pubdate = $item->pubDate();
        $pubdate =~ s/\.[0-9]{3}//;
        my $dt = $strp->parse_datetime($pubdate);
        my $post_timestamp =  $dt->strftime('%s');
        
       
       if ($title =~ m{^\s* 
                <a\s*href=[^>]+>\s*([^<>]+)\s*</a>\s* # the name
                    ((:?re)?opened|closed|created)\s* # what they do?
        <}ix)
        {
            my $name = $1;
            my $did = lc($2);
            my $title = $hs->parse(substr($title, ($+[0]) - 1));
            $title =~ s/\s+/ /gm;
            $title =~ s/\s*$//;
            my $link = $item->link();
            my $feedkey;
            $feedkey = $1 if ($title =~ m|^([A-Z]+)-[0-9]+|);

            $log->trace("Got news from $name about $did '$title' for feed $feedkey... parsing. a little more");

            if ($feedkey && $$feeds{$feedkey})
            {
                # Make sure to initialise the timestamp for the news item
                $$feeds{$feedkey}{timestamp}||=0;
    
                if ($post_timestamp <= $$feeds{$feedkey}{timestamp})  {
                    # Hers what happens with _OLD_ news
                    $log->debug(sprintf ("Jira feed:%s post_timestamp %s is older than latest stored timestamp: %s", 
                                    $feedkey,  $post_timestamp,  $$feeds{$feedkey}{timestamp}));
                    next;
                } elsif ($nowt->subtract_datetime_absolute($dt)->delta_seconds > 360000) {
                    # and  to prevent gutta from rambling old stuff because he's been out of sync
                    $log->warn( sprintf ("Jira feed:%s datetime from post %s is more than 1 hours older than current time %s", 
                                    $feedkey, $dt->strftime('%F %T'), $nowt->strftime('%F %T')));
                    next;
                } else {
                    # Is this the latest new (making no assumption on the order of the news recieved...)
                    if ($post_timestamp > $latest_timestamp{$feedkey})
                    {
                        # OK store the latest timestamp.
                        $latest_timestamp{$feedkey} = $post_timestamp;
                    }
    
                    push @{$news{$feedkey}}, sprintf ("%s %s %s (%s)\n", $name, $did, $title, $link);
                    $log->info(sprintf ("OK %s %s %s (%s)\n", $name, $did, $title, $link));
    
                }
            } else {
                    $log->warn("UNCONFIGURED FEED $feedkey for news from $name about $did '$title'. This should not happen");
            }
        } 


    }
    # OK update timestamps in the persistent hash.
    while (my ($feedkey, $timestamp) = each %latest_timestamp)
    {
        $$feeds{$feedkey}{timestamp} = $timestamp;
    }
    # And saving it!!
    $self->save();
}

sub __download_jira_feed
{
    #Download from the jira feed.
    # it will search for KEY=$feedkay key.is+$feedkey
    my $self = shift;
    my @feedkeys = @_;
    my $url = $self->get_config('url');
    my $username = $self->get_config('username');
    my $password = $self->get_config('password');

    # double check that there is a valid URL.
    return 0, "please set url to download the feed" unless $url;

    my $ua = LWP::UserAgent->new;
    # https://jira.atlassian.com/activity?maxResults=10&streams=key+IS+CONF+OR+CQ+OR+BAM
    my $feedURL = sprintf("https://%s/activity?maxResults=20&streams=key+IS+%s", $url, join('+OR+', @feedkeys));
    $log->debug("Attempting a download of   [$feedURL]");

    my $req = HTTP::Request->new(GET => $feedURL);
    if ($username && $password)
    {
        warn("settting authirization headers $username and $password") ;
        $req->authorization_basic($username, $password);
    }
    my $response =  $ua->request($req);


     if ($response->is_success) {
         return 1, $response->decoded_content;
     }
     else {
         return 0, $response->status_line;
     }
}

sub get_jira_issue
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $issue_id = shift;
    my $url = $self->get_config('url');
    my $username = $self->get_config('username');
    my $password = $self->get_config('password');

    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => "https://${url}/rest/api/2/issue/${issue_id}");
    $req->header( 'Content-Type' => 'application/json');
    if ($username && $password)
    {
        $log->debug("settting auth headers $self->{data}{'username'},") ;
        $req->authorization_basic($username, $password);
    }

    my $response =  $ua->request($req);

    my $issue = from_json($response->decoded_content, { utf8 => 1 });


    # Make sure there was a match.
    if (defined $$issue{'fields'}{'summary'})
    {
        return sprintf("msg %s %s: %s (https://%s/issues/%s)", 
            $target, $issue_id, $$issue{'fields'}{'summary'}, $url, $issue_id);
    }
    
    # if not - don't return anything ...
    return undef;


}
#
#   work with jira users
#
#

sub set_jira_user
{
    my $self = shift;
    my $nick = shift;
    my $jira_username = shift;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare('INSERT OR REPLACE INTO jira_users (nick,jira_username) VALUES(?,?)');
    # TODO handle errors.
    $sth->execute($nick,$jira_username);

}

sub get_jira_user
{
    my $self = shift;
    my $nick = shift;
    my $dbh = $self->dbh();
    warn ("GETTING THE USERNAME FOR $nick ... \n");

    my $sth = $dbh->prepare('SELECT jira_username from jira_users WHERE nick = ?') or warn $dbh->errstr;
    # TODO handle errors.
    $sth->execute($nick) or $log->warn($dbh->errstr);


    my ($jira_username) = $sth->fetchrow_array();
    $log->debug("GOT $jira_username \n");

    return $jira_username;
}

1;
