package Gutta::DBI;
use base 'Class::Singleton';

use warnings;
use strict;
use DBI;

=head1 NAME

Gutta::DBI

=head1 SYNOPSIS

Provides the SQLite DBI for Gutta.


=head1 DESCRIPTION

Most of the things known by gutta will be stored here for later use.

=cut

sub _new_instance 
{
    my $class = shift;
    my $self  = bless { }, $class;
    my $db    = shift || "Gutta/Data/gutta.db";    
        
    $self->{ dbh } = DBI->connect("dbi:SQLite:dbname=${db}","","")
         || die "Cannot connect to database: $DBI::errstr";
        

     my $dbh = $self->{dbh};
     # my $sth = $dbh->prepare("SELECT SQLITE_VERSION()");
     # $sth->execute();

    return $self;
}

sub dbh
{
    my $self = shift;
    return $self->{dbh};
}

1;
