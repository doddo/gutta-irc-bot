package Gutta::Plugins::Support;

use parent Gutta::Plugins::Jira;

use JSON;

sub process_msg
{
	my $self = shift;
	my $msg = shift;
	my $nick = shift;
	my $mask = shift;
	my $target = shift;

	if ($msg =~ s/^!support\s+//)
	{ 
		unless ($self->{data}{users}{$nick}) {
			return "msg $target I don't know who you: $nick are.";
		}

		my @ts;
		while ($msg =~ s/(\d{1,10})\s*([mhwd])\b//)
		{
			push (@ts, $1 . $2); 
		}

		my $summary = $msg;
		my $duration = join(" ", @ts);

		my $issue = $self->create_jira_support_issue($summary, $nick);
		$self->log_work_on_jira_issue($issue, $duration);
		$self->close_jira_support_issue($issue);

		return "action $target created support ticket: $issue";
	} else { 
		return ();
	}
}

sub _initialise
{
	my $self = shift;
	$self->SUPER::_initialise($self);
}

sub _heartbeat_act
{
    return ;
}




sub create_jira_support_issue
{
	my $self = shift;
	my $summary = shift;
	my $nick = shift;

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://$self->{data}{url}/rest/api/2/issue/");
	my $json = '{"fields":{"project":{"key":"NAMS"},"assignee":{"name":"' . $self->{data}{users}{$nick} . '"},"summary":"' . $summary . '","issuetype":{"name": "Ticket"}}}';
	$req->content($json);

	my $response = $ua->request($req);
	my $issue = from_json($response->decoded_content, { utf8 => 1 });

	return $$issue{'key'};
}

sub log_work_on_jira_issue
{
	my $self = shift;
	my $issue = shift;
	my $duration = shift;

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://$self->{data}{url}/rest/api/2/issue/${issue}/worklog");
	my $json = '{"timeSpent":"' . $duration . '"}';
	$req->content($json);

	my $response = $ua->request($req);
}

sub close_jira_support_issue
{
	my $self = shift;
	my $issue = shift;

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://$self->{data}{url}/rest/api/2/issue/${issue}/transitions");
	my $json = '{"fields":{"resolution":{"name": "Fixed"},"fixVersions":[{"id":"19678","name": "SUPPORT"}]},"transition":{"id":"2"}}';
	$req->content($json);

	my $response = $ua->request($req);
}

sub setup_request_context
{
	my $self = shift;
	my $method = shift;
	my $url = shift;

	my $req = HTTP::Request->new($method => $url);
	$req->header('Content-Type' => 'application/json');

	if ($self->{data}{'username'} && $self->{data}{'password'})
	{
		$req->authorization_basic($self->{data}{'username'}, $self->{data}{'password'});
	}

	return $req;
}
1;
