package Gutta::Plugins::Support;

use parent 'Gutta::Plugins::Jira';

use Data::Dumper;
use JSON;

sub process_msg
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
 
	my $jira_user = $self->get_jira_user($nick);
	warn Dumper($nick);
	warn Dumper($jira_user);


	unless ($jira_user) {
		return "msg $target I don't know who you: $nick are.";
	}

	my @ts;
	while ($rest_of_msg =~ s/(\d{1,10})\s*([mhwd])\b//)
	{
		push (@ts, $1 . $2); 
	}

	my $summary = $rest_of_msg;
	my $duration = join(" ", @ts);

	my $issue = $self->create_jira_support_issue($summary, $jira_user);
	$self->log_work_on_jira_issue($issue, $duration);
	$self->close_jira_support_issue($issue);

	return "action $target created support ticket: $issue";
}

sub _triggers
{
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    my $self = shift;

    return;
}

sub _commands
{
    # The commands for JIRA plugin.
    my $self = shift;

    return {
        'support' => sub { $self->process_msg(@_) },
    };
}

sub _heartbeat_act
{
    return ;
}


sub create_jira_support_issue
{
	my $self = shift;
	my $summary = shift;
	my $jira_user = shift;
        my $url = $self->get_config('url', 'Gutta::Plugins::Jira');

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://${url}/rest/api/2/issue/");
	my $json = '{"fields":{"project":{"key":"NAMS"},"assignee":{"name":"' . $jira_user  . '"},"summary":"' . $summary . '","issuetype":{"name": "Ticket"}}}';
	$req->content($json);

	my $response = $ua->request($req);
	warn Dumper($response);
	my $issue = from_json($response->decoded_content, { utf8 => 1 });

	return $$issue{'key'};
}

sub log_work_on_jira_issue
{
	my $self = shift;
	my $issue = shift;
	my $duration = shift;
        my $url = $self->get_config('url', 'Gutta::Plugins::Jira');

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://${url}/rest/api/2/issue/${issue}/worklog");
	my $json = '{"timeSpent":"' . $duration . '"}';
	$req->content($json);

	my $response = $ua->request($req);
}

sub close_jira_support_issue
{
	my $self = shift;
	my $issue = shift;
        my $url = $self->get_config('url', 'Gutta::Plugins::Jira');

	my $ua = LWP::UserAgent->new;
	my $req = $self->setup_request_context('POST', "https://${url}/rest/api/2/issue/${issue}/transitions");
	my $json = '{"fields":{"resolution":{"name": "Fixed"},"fixVersions":[{"id":"19678","name": "SUPPORT"}]},"transition":{"id":"2"}}';
	$req->content($json);

	my $response = $ua->request($req);
}

sub setup_request_context
{
	my $self = shift;
	my $method = shift;
	my $url = shift;
        my $username = $self->get_config('username', 'Gutta::Plugins::Jira');
        my $password = $self->get_config('password', 'Gutta::Plugins::Jira');



	my $req = HTTP::Request->new($method => $url);
	$req->header('Content-Type' => 'application/json');

	if ($password and $username)
	{
		$req->authorization_basic($username, $password);
	}

	return $req;
}
1;
