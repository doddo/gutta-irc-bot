package Gutta::Plugins::Jira;
# does something with Jira

use parent Gutta::Plugin;

use LWP::UserAgent;
use HTML::TokeParser;
use MIME::Base64;
use JSON;
use strict;
use warnings;
use Data::Dumper;

sub process_msg
{
    my $self = shift;
    my $msg = shift;
    # word boundries does not seem to work???
    if ($msg =~ /\b([A-Z]{3,30}-[1-9]{1,7})\b/) 
    { 
       return "unset url." unless $self->{data}{'url'};
       return $self->get_jira_request($1);
    } elsif ($msg =~ /!jira set (username|password|url)=(\S+)\b/ ) {
        # TODO: this will be replaced at later time
        $self->{data}{$1} = $2;
        $self->save();
        return "OK - [$1] set to [$2]";
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

sub get_jira_request
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
