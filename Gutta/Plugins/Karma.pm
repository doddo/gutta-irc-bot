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
    my $mask = shift;
    my $target = shift;

    my $save = 0;
    my @response;
                     # Maybe rewritethis  
    while ($msg =~ m/([a-z0-9_@.ÅÄÖåäö]+?)(\+\+|--)/ig)
    {
         push @response, $self->karma($1,$2,$nick, $target);
         $save = 1;
    }

    if ($msg =~ m/^srank\s*(\S+)?/) {
        @response = $self->srank($1, $target);
    }

    $self->save() if $save;

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
    my $karma_item = shift; # what to give karma to
    my $modifier = shift; # ++ or --
    my $nick = shift;  # the nick calling 
    my $target = shift; # the channel


    if (($modifier eq '++') and 
        (lc($nick) ne lc($karma_item)))
    {
      $self->{data}{lc($karma_item)}++;
    } else {
      $self->{data}{lc($karma_item)}--;
    }
    
    return "msg ${target} ${karma_item} now has " . $self->{data}{lc($karma_item)} . " points of karma." ;
}

sub srank
{
    # Get rank list and filder by optional $karma_item (regex)
    my $self = shift;
    my $karma_item = shift; # what items to ask karma from
    my $target = shift; # what channel etc
    my @sranks; # return this list of srank commands
    warn("OK KALLE");
    my @karmalist = sort { $self->{data}{$b} <=> $self->{data}{$a} } keys %{$self->{data}};
    @karmalist = grep(/$karma_item/i, @karmalist) if $karma_item;
    foreach (@karmalist)
    {
        push(@sranks, sprintf('msg %s %s (%s)', $target, $_, $self->{data}{$_}));
        last if (scalar @sranks >10);
    }
    return @sranks;
}

1;
