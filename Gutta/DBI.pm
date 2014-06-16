package Gutta::DBI;

use warnings;
use strict;
use DBI;
use Gutta::Constants qw/DBFILE/;

=head1 NAME

Gutta::DBI

=head1 SYNOPSIS

Provides the SQLite DBI for Gutta.


=head1 DESCRIPTION

Most of the things known by gutta will be stored here for later use.

=cut

sub instance 
{
    my $class = shift;
    my $self  = bless { }, $class;

    return $self;
}

sub dbh
{
    my $self = shift;
    my $db = DBFILE;
    $self->{ dbh } = DBI->connect("dbi:SQLite:dbname=${db}","","")
         || die "Cannot connect to database: $DBI::errstr";
     return $self->{ dbh };
}

1;
