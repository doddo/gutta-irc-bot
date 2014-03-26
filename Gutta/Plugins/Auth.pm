package Gutta::Plugins::Auth;
use parent Gutta::Plugin;
# A special plugin to handle authentication.

use strict;
use warnings;
use DateTime;
use Gutta::Users;
use Data::Dumper;

=head1 NAME

Gutta::Plugins::Auth


=head1 SYNOPSIS

Provides "authentication support" for gutta.


=head1 DESCRIPTION

Uses the Gutta::Users and DB handle to handle users.

then they can identify, have different access levels or what ever.

some commands should only be run by "trusted" people, and this is to prevent untrusted users from abusing guttas power.

=cut


sub _initialise
{
    # initialising the auth module
    my $self = shift;
    #
    $self->{users} = Gutta::Users->new();
    $self->{sessions} = {};
    $self->{sessions_ttl} = 10800; # keep "session" for this long

    $self->_dbinit("sessions");
}


sub _commands
{
    my $self = shift;
    # the commands for the auth plugin.
    return {

        'identify' => sub { $self->process_cmd('identify', @_) },
        'register' => sub { $self->process_cmd('register', @_) },
         'session' => sub { $self->process_cmd('session', @_) },
          'passwd' => sub { $self->process_cmd('passwd', @_) },
    }
}

sub process_cmd
{
    my $self = shift;
    my $command = shift; #identify or register
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;

    # make sure they dont chat about these things publicly
    if ($target =~ /^#/) 
    {
        return "msg $target $nick: please talk about these things over private channel...";    
    }

    if ($command eq 'identify')
    {
        return "msg $nick usage: identify <password>" unless $rest_of_msg;
        warn "idenfiying $nick with [$rest_of_msg]";
        return $self->identify($nick, $rest_of_msg, $mask);
        

    } elsif ($command eq 'session') {
        
        if (my $expire_date = $self->has_session($nick, $mask))
        {
            return "msg $nick OK - you are logged in until $expire_date";
        } else {
            return "msg $nick SOZ, u are NOT logged in";
        }

    } elsif ($command eq 'register') {
        return "msg $nick usage: register <password>" unless $rest_of_msg;
        my ($password, $email) = split/\s/, $rest_of_msg;
        return $self->register_nick($nick, $nick, $password, $email);
    } elsif ($command eq 'passwd') {
        return "msg $nick TODO: This feature is not programmed yet";
    }

}

sub has_session
{
    # "returns whether the user has a session or not.
    my $self = shift;
    return $self->{users}->has_session(@_);
}

sub register_nick
{
    # register a new user with gutta
    my $self = shift;
    my $target = shift;
    my $nick = shift;
    my $password = shift or return "msg $target Usage: identify password";
    my $email = shift;
    

    if ($self->{users}->get_user($nick))
    {
        return "msg $target $nick is already in the system.";

    } else {
        return "msg $target $nick " .  $self->{users}->useradd($nick, $password, $email);
    }
}

sub identify
{
    # identify
    my $self = shift;
    my $target = shift;
    my $nick = shift;
    my $password = shift;
    my $mask = shift;
    
    if (my $user = $self->{users}->get_user($nick))
    {      
        warn Dumper($user);
        if ($self->{users}->_hash($password, $$user{$nick}{salt}) eq $$user{$nick}{password})
        {
            $self->_login_user($nick, $mask) or return "msg $target something unknown went wrong\n";
            return "msg $target OK - $nick logged in."
        } else {
            return "msg $target Not OK - invalid password for $nick."
        }
    } else {
        return "msg $target $nick is not in the system."
    }
}

sub _login_user
{
    # sets the session for the user
    my $self = shift;
    my $nick = shift;
    my $mask = shift;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare(qq{INSERT OR REPLACE INTO sessions (nick, mask, session_expire) VALUES (?, ?, ?)});
    $sth->execute($nick, $mask, (time + $self->{sessions_ttl})) or return undef;

    return 1;
}


sub _setup_shema
{
    my $self = shift;
    return <<EOM
    CREATE TABLE IF NOT EXISTS sessions (
                nick TEXT NOT NULL PRIMARY KEY,
                mask TEXT NOT NULL,
      session_expire INT NOT NULL,
    FOREIGN KEY(nick) REFERENCES users(nick)
    );
EOM
;
}

1;
