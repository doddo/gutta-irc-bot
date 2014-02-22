package Gutta::Plugins::Karma;
use parent Gutta::Plugin;
# A module to to manage karma
use strict;
use warnings;

sub process_msg
{
    my $self = shift;
    my $msg = shift;
    my $nick = shift;
    my $save = 0;
    my @response;
                     # Maybe rewritethis  
    while ($msg =~ m/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/ig)
    {
         push @response, $self->karma($1,$2,$nick);
         $save = 1;
    }

    if ($msg =~ m/^srank\s*(\S+)?/) {
        @response = $self->srank($1);
    }

    $self->save();

    return @response;
}

sub _initialise
{
    my $self = shift;
    $self->{datafile} = "Gutta/Data/" . __PACKAGE__ . ".data",
    $self->load() # load the karma file
}

sub karma
{
    my $self = shift;
    my $target = shift;
    my $modifier = shift;
    my $user = shift;


    if (($modifier eq '++') and 
        (lc($user) ne lc($target)))
    {
      $self->{data}{lc($target)}++;
    } else {
      $self->{data}{lc($target)}--;
    }
    
    return "$target now has " . $self->{data}{lc($target)} . " points of karma." ;
}

sub srank
{
    # Get rank list and filder by optional $target (regex)
    my $self = shift;
    my $target = shift;
    my @sranks;
    warn("OK KALLE");
    my @karmalist = sort { $self->{data}{$b} <=> $self->{data}{$a} } keys %{$self->{data}};
    @karmalist = grep(/$target/i, @karmalist) if $target;
    foreach (@karmalist)
    {
        push(@sranks, $_ . " (" . $self->{data}{$_} .")");
        last if (scalar @sranks >10);
    }
    return @sranks;
}

1;
