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


sub process_privmsg
{
    my $self = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;

    warn "processing privmsg for Auth\n";

    if ($msg =~ m/^identify (\S+)/)
    {
        warn "idenfiying $nick with  $1";
        $self->identify($nick, $nick, $1, $mask);
    } elsif ($msg =~ m/^session/i) {
        if (my $expire_date = $self->has_session($nick, $mask))
        {
            return "msg $nick OK - you are logged in until $expire_date"
        } else {
            return "msg $nick SOZ, u are NOT logged in"
        }
    } elsif ($msg =~ m/^register\s+(\S+)\s*(\S+)?/) {
        my $password = $1;
        my $email;
        $email = $2 if $2;

        return $self->register_nick($nick, $nick, $password, $email);
    }


}

sub has_session
{
    # "booelan" returns whether the user has a session or not.
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare("SELECT mask, session_expire FROM sessions WHERE nick = ?");
    $sth->execute($nick);
    my ($smask, $session_expire) = $sth->fetchrow_array();
        

    if ($smask eq $mask and $session_expire >= time)
    {
        warn ("user is  logged in");
        return $session_expire;  # true
    }
    else
    {
        warn ("user was not logged in: $session_expire");
        return undef; # False
    }
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
    # register a new user with gutta
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
    CREATE TABLE sessions (
            nick TEXT NOT NULL PRIMARY KEY,
                mask TEXT NOT NULL,
      session_expire INT NOT NULL,
    FOREIGN KEY(nick) REFERENCES users(nick)
    );
EOM
;
}

1;
