package Gutta::Plugins::Jira;
# does something with Jira

use parent Gutta::Plugin;

use HTML::Strip;
use LWP::UserAgent;
use XML::FeedPP;
use MIME::Base64;
use JSON;
use XML::Feed;
use strict;
use warnings;
use Data::Dumper;
use DateTime::Format::Strptime;
use Getopt::Long qw(GetOptionsFromArray);


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


=cut


sub process_msg
{
    my $self = shift;
    my $msg = shift;
    return undef unless $msg;
    # word boundries does not seem to work???
    if ($msg =~ /\b([A-Z]{3,30}-[1-9]{1,7})\b/) 
    { 
       return "unset url." unless $self->{data}{'url'};
       return $self->get_jira_issue($1);
    } elsif ($msg =~ /!jira set (username|password|url)=(\S+)\b/ ) {
        # TODO: this will be replaced at later time
        $self->{data}{$1} = $2;
        $self->save();
        return "OK - [$1] set to [$2]";
    } elsif ($msg =~ /!jira feed/){
        return $self->__setup_jira_feed(split(/\s+/,$msg));
    } elsif ($msg =~ /!jira Dump/ ) {
        # TODO: fix this 
        return Dumper($self->{data});
    } else { 
       return undef;
    }
}

sub _initialise
{
    my $self = shift;
    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",
    $self->load(); # load the karma file
}

sub __setup_jira_feed
{
    # the command line interface
    # for configuring feeds
    # it is a little ugly but will be fixed sometime
    my $self = shift;
    shift; #jira
    shift; #feed
    my $action = shift;
    my $feedkey = shift;
    my @args = @_;
    my $feed;
    if ($action eq 'del')
    {
        undef($self->{data}{feeds}{$feedkey});
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
    );

    $self->save();
    return sprintf ("adding feed '%s' servers '%s' and channels '%s'",
                   $feedkey, join(',', @{$$feed{server}}), join(',', @{$$feed{channel}}));

}

sub monitor_jira_feed
{
    my $self = shift; 
    my $feeds = \%{$self->{data}{feeds}};
    my $hs = HTML::Strip->new();
    my $strp = DateTime::Format::Strptime->new(
        pattern   => "%Y-%m-%dT%H:%M:%S%Z",
        on_error  => 'croak',
    );
    my @news;
    my $latest_timestamp = 0;
    my $nowt = DateTime->now();


    foreach my $feedkey (keys %{$feeds})
    {
       $$feeds{$feedkey}{timestamp}||=0;
#        my @report_to_channels = @{$$feeds{$feedkey}{'channel'}};
#        my @report_to_servers = @{$$feeds{$feedkey}{'server'}};
    
       my ($status, $feeddata) = $self->__download_jira_feed($feedkey);

       unless ($status)
       {
           warn ("unable to download for feed $feedkey: $feeddata\n");
           next;
       }
       
       my $feed = XML::FeedPP->new( $feeddata );


       foreach my $item ( $feed->get_item() ) 
       {
       #        print "URL: ", $item->link(), "\n";
            my $title = $item->title();

            # parse the pubdate from the item (the news item)
            my $pubdate = $item->pubDate();
            $pubdate =~ s/\.[0-9]{3}//;
            my $dt = $strp->parse_datetime($pubdate);
            my $post_timestamp =  $dt->strftime('%s');

           if ($post_timestamp <= $$feeds{$feedkey}{timestamp})  {
                # Hers what happens with _OLD_ news
                warn sprintf ("Jira feed:%s post_timestamp %s is older than latest stored timestamp: %s", 
                                $feedkey,  $post_timestamp,  $$feeds{$feedkey}{timestamp});
                next;
            } elsif  ($nowt->subtract_datetime_absolute($dt)->delta_seconds > 360000) {
                # and  to prevent gutta from rambling old stuff because he's been out of sync
                warn sprintf ("Jira feed:%s datetime from post %s is more than 1 hours older than current time %s", 
                                $feedkey, $dt->strftime('%F %T'), $nowt->strftime('%F %T'));
                next;
           } 
           
            
            
            if ($title =~ m{^\s* 
                    <a\s*href=[^>]+>\s*([^<>]+)\s*</a>\s* # the name
                        ((:?re)?opened|closed|created)\s*  # what they do?
            <}ix)
            {
                my $name = $1;
                my $did = lc($2);
                my $title = $hs->parse(substr($title, ($+[0]) - 1));
                $title =~ s/\s+/ /gm;
                $title =~ s/\s*$//;
                my $link = $item->link();
                
                push @news, sprintf ("%s %s %s (%s)\n", $name, $did, $title, $link);
                print sprintf ("OK %s %s %s (%s)\n", $name, $did, $title, $link);
                $latest_timestamp = $post_timestamp if ( $post_timestamp  > $latest_timestamp);
           }
        }
        if ($$feeds{$feedkey}{timestamp} < $latest_timestamp)
        {
            $$feeds{$feedkey}{timestamp} = $latest_timestamp ;
            $self->save();
        }
    }
}

sub __download_jira_feed
{
    #Download from the jira feed.
    # it will search for KEY=$feedkay key.is+$feedkey
    my $self = shift;
    my $feedkey = shift;

    my $ua = LWP::UserAgent->new;
    my $feedURL = sprintf("https://%s/activity?maxResults=10&streams=key+IS+%s", $self->{data}{url}, $feedkey);

    my $req = HTTP::Request->new(GET => $feedURL);
    if ($self->{data}{'username'} && $self->{data}{'password'})
    {
        warn("settting authirization headers $self->{data}{'username'},XXXXXX") ;
        $req->authorization_basic($self->{data}{'username'},  $self->{data}{'password'});
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
    # TODO: Fix this later
    my $issue_id = shift;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => "https://$self->{data}{url}/rest/api/2/issue/${issue_id}");
    $req->header( 'Content-Type' => 'application/json');
    if ($self->{data}{'username'} && $self->{data}{'password'})
    {
        warn("settting authirization headers $self->{data}{'username'},  $self->{data}{'password'}");
        $req->authorization_basic($self->{data}{'username'},  $self->{data}{'password'});
    }
    my $response =  $ua->request($req);

    my $issue = from_json($response->decoded_content, { utf8 => 1 });

    return sprintf("%s: %s (https://%s/issues/%s)", $issue_id, $$issue{'fields'}{'summary'}, $self->{data}{url}, $issue_id);
}

1;
