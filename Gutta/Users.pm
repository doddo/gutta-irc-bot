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

sub _setup_shema 
{
    my $self = shift;
    return <<EOM
    CREATE TABLE users   (
              username TEXT PRIMARY KEY,
              password TEXT NOT NULL,
                 email TEXT,
                  salt INTEGER NOT NULL,
               created INTEGER NOT NULL,
            last_login INTEGER, 
  last_password_change INTEGER  )

EOM
;
}

sub _dbinit
{
    # make sure table exists, or else create a new one.
    my $self = shift;
    my $primary_table = shift || $self->{primary_table};
    my $table;
    
    my $dbh = $self->dbh();

    my $sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?");
    $sth->execute($primary_table);

    print "found table $table\n" while ($table = $sth->fetchrow_array());
    
    if ($sth->rows == 0)
    {
        warn "creating table for $primary_table\n";
        my $sth = $dbh->prepare($self->_setup_shema()) or die "unable to do " , $self->_setup_shema() , ":$!\n";
        $sth->execute() or die "unable to do " , $self->_setup_shema() , ":$!\n"; 
    }

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
    my $username = shift;
    my $password = shift;
    my $email = shift;
    my $salt = "Bamse";
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{
        INSERT INTO users (username, password, email, salt, created, last_password_change)
          VALUES (?,?,?,?,?,?)});
    $sth->execute($username, $self->_hash($password, $salt), $email, $salt, time, time) or warn ("uanble to add user $username :$!\n");

}

sub userdel
{
    # del a user
    my $self = shift;
    my $username = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{DELETE FROM users where name = ?});
    $sth->execute($username);
}

sub usermod
{
    # A little ugly this one
    my $self = shift;
    my $username = shift;

    my @changes=@_;
    # TODO: implement this

}


sub passwd
{
    # set new password, but NOT validate the old one (because thats going to happen in the auth module)
    # Maybe next versuib will support this.   
    my $self = shift;
    my $username = shift;
    my $password = shift;
    my $salt = "TODO";
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{UPDATE users SET password = ?, salt = ? WHERE username = ?});
    $sth->execute($self->_hash($password, $salt), $salt, $username);
    return $?;
}

sub get_user
{
    # returns user
    my $self = shift;
    my $username = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{SELECT email, created FROM users WHERE username = ?});
    $sth->execute($username);

    return $sth->fetchall_hashref('username');
}

sub get_users
{
    # returns user
    my $self = shift;
    my $username = shift;
    my $dbh = $self->dbh();    

    my $sth = $dbh->prepare(qq{SELECT username, email, created FROM users});
    $sth->execute();

    return $sth->fetchall_hashref('username');
}

1;
