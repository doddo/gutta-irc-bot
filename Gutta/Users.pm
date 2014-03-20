package Gutta::Users;
use Gutta::DBI;
use Storable;
use strict;
use warnings;
use DateTime;
use Data::Dumper;
use Crypt::PasswdMD5;


=pod

Manage Gutta users.

They are mapped <-> irc nics/addresses
etc


=cut


sub new 
{
    my $class = shift;

    my $self = bless {
               db => Gutta::DBI->instance(),
    primary_table => 'users'
    }, $class;

    $self->_dbinit('users');
    return $self;

}

sub dbh
{
    # return the DB handle.
    my $self = shift;

    return $self->{db}->dbh();

}

sub _dbinit
{
    # DBinit provides support for to initialise their db:s, 
    # it runs the sql from the _setup_shema method
    # the $self->setup_shema() class.
    # this can be called multiple times by passing different tables to setup_schema
    my $self = shift;
    my $dbh = $self->dbh();

    my $query = qq{
            CREATE TABLE IF NOT EXISTS users   (
                          nick TEXT PRIMARY KEY,
                      password TEXT NOT NULL,
                         email TEXT,
                          salt INTEGER NOT NULL,
                       created INTEGER NOT NULL,
                    last_login INTEGER, 
          last_password_change INTEGER  )
    }

    my $sth = $dbh->prepare($query) or die "unable to run: $query\n";
    $sth->execute() or  die "unable to execute; $query\n";
}



sub _hash
{
    my $self = shift;
    my $password = shift;
    my $salt = shift;

    return unix_md5_crypt($password,  $salt);
}

sub useradd
{
    # add new user
    my $self = shift;
    my $nick = shift;
    my $password = shift;
    my $email = shift;
    my $salt = "Bamse";
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{
        INSERT INTO users (nick, password, email, salt, created, last_password_change)
          VALUES (?,?,?,?,?,?)});
    $sth->execute($nick, $self->_hash($password, $salt), $email, $salt, time, time) or warn ("uanble to add user $nick :$!\n") or return "unable to add the user ... $!";
    
    return "OK - added $nick with $email."
}

sub userdel
{
    # del a user
    my $self = shift;
    my $nick = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{DELETE FROM users where name = ?});
    $sth->execute($nick);
}

sub usermod
{
    # A little ugly this one
    my $self = shift;
    my $nick = shift;

    my @changes=@_;
    # TODO: implement this

}


sub passwd
{
    # set new password, but NOT validate the old one (because thats going to happen in the auth module)
    # Maybe next versuib will support this.   
    my $self = shift;
    my $nick = shift;
    my $password = shift;
    my $salt = "TODO";
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{UPDATE users SET password = ?, salt = ? WHERE nick = ?});
    $sth->execute($self->_hash($password, $salt), $salt, $nick);
    return $?;
}

sub get_user
{
    # returns user
    my $self = shift;
    my $nick = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{SELECT nick, email, created, salt, password FROM users WHERE nick = ?});
    $sth->execute($nick);

    my $userdata =  $sth->fetchall_hashref('nick');

    return undef if $sth->rows == 0;
    return $userdata;
    

}

sub get_users
{
    # returns user
    my $self = shift;
    my $nick = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{SELECT nick, email, created FROM users});
    $sth->execute();

    my $userdata =  $sth->fetchall_hashref('nick');

    return undef if $sth->rows == 0;
    return $userdata;
}

1;
