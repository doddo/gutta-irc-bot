package Gutta::Plugins::Aop;
use warnings;
use parent 'Gutta::Plugins::Auth';
use strict;
use Gutta::Users;
use Gutta::Session;
use Gutta::Plugins::Auth;
use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);
use v5.10;


=head1 NAME

Gutta::Plugins::Aop

=head1 SYNOPSIS

Instruct bot to automatically handle op:ing nicks in channels.


=head1 DESCRIPTION

Provides support for having the bot automatically add nicks when joining and 
upon request.

=head1 aop

Handle aop:ing the incoming nick. aop:s get op, but first they need to !register.


  !aop [ info | [ add | del | modify ] NICK [ --channel C ] [ --lvl INT ] ] 

=over 8

=item B<--channel>

What channel (if in a channel and ommitted, will assume it current channel)

=item B<--level>

The level is a number between 0-100. an aop can only add someone with less level
than itself has. A number above 1 means that the user will be oped, (but can't op)

=back

=head1 op

used to give op to a user. 
If channel is omitted, it will assume current channel.
If is omitted, it will assume current channel.

  !op [ channel ] [ nick ]

=cut


my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub _initialise
{
    # THe constructor in the parent class calls for this.
    my $self = shift;

    $self->{ session } = Gutta::Session->instance();
    $self->{ auth } = Gutta::Plugins::Auth->new();
    $self->{ users } = Gutta::Users->new();
    $self->_dbinit(); 
}


sub _setup_shema
{
    my $self = shift;

    my @queries  = (qq{
    CREATE TABLE IF NOT EXISTS aops (
               nick TEXT NOT NULL,
            channel TEXT NOT NULL,
                lvl INTEGER,
    FOREIGN KEY(nick) REFERENCES users(nick),
      CONSTRAINT nick_per_chan UNIQUE (nick, channel)
    )}, qq{
    CREATE VIEW IF NOT EXISTS aop_sessions AS 
            SELECT a.nick,
                   a.mask,
                   b.channel,
                   b.lvl
              FROM sessions a
        INNER JOIN aops b
                ON a.nick = b.nick
    });

    return ($self->SUPER::_setup_shema(), @queries);
}

sub _event_handlers
{
    my $self = shift;
    return {

        'JOIN' => sub { $self->on_join(@_) },

    }
}

sub _commands
{
    my $self = shift;
    return {

        'aop' => sub { $self->process_cmd('aop', @_) },
         'op' => sub { $self->process_cmd('op', @_) },

    }
}

sub on_join
{
    my $self = shift;
    my $timestamp = shift;
    my $server = shift;
    my @payload = @_;    

    # they need someonw to aop
    $log->debug(Dumper(@payload));


    return "";
}

sub process_cmd
{
    my $self = shift;
    my $cmd = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;

    # some vars used ...
    my @responses;
    my @rest_of_msg;
    my $subcmd;
    my $target_nick;

    # Possble subcmd...
    if ($rest_of_msg)
    {
        ($subcmd, @rest_of_msg) = split(' ',$rest_of_msg);
        if (@rest_of_msg)
        {
            $target_nick = shift(@rest_of_msg);
        }
    }

    # OK do they want OP?
    if ($cmd eq 'op')
    {
        $self->__handle_op($nick, $mask, $target, @rest_of_msg);
    } elsif ($cmd eq 'aop'){
        if ($subcmd ~~ ["add", "del", "modify"])
        {
            push @responses, 
                $self->__nickmod($subcmd, $nick, $mask, $target, $target_nick, @rest_of_msg);
        }
    }

    return @responses;
}

sub __handle_op
{
    my $self = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my @rest_of_msg = @_;

    # TODO

    return ;

}

sub __nickmod
{
    # Adds a nick to be automatically op:ed ...
    my $self = shift;
    my $subcmd = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $target_nick = shift;
    my @args = @_; 
    
    # Parse options...
    my $channel;
    my $level;
    my $lvl;

    GetOptionsFromArray(\@args,
          'channel=s' => \$channel,
              'lvl=i' => \$lvl)
    or return "invalid options supplied";

    #
    # Has the user logged in to the system?
    #
    return "msg $target please identify first." unless $self->{ auth }->has_session($nick, $mask); 

    # Validate lvl if there is one.
    if ($lvl && ($lvl < 0 || $lvl > 100))
    {
        return "msg $target invalid lvl supplied:$lvl, should be between 0-100";
    }
    
    # Figure out who is the target
    unless ($target_nick)
    {
        return "msg $target missing target nick.";
    }

    # Figure out in what channel to target.
    if ($channel)
    {
        unless ($channel =~ m/^#+[a-z_0-9]{1,100}\b/i)
        {
            return "msg $target '$channel' does not validate as channel";
            $log->info("${nick} supplied an invalid channel '${channel}'...");
        }

    } elsif ($target =~ m/^#/){
        $log->debug("No --channel option supplied, falling back to $target...");
        $channel = $target;
    } else {
        # Bot does not know what channels this is about.
        return "msg $target unable to compute; don't know what --channel...";
    }


    # Check if $target_nick is registered ...
    unless (my $registered_user = $self->{ users }->get_user($target_nick))
    {
        return "msg $target tell $target_nick hen needs to register first ...";
    }


    $log->info(sprintf 'regged user %s requested regged user %s to be %s',
                                                $nick, $target_nick,  $subcmd);

    # Gather system information about $target_nick.
    my $target_nickinfo = $self->__get_info_about_nick($target_nick, $channel);
    my $source_nickinfo;


    #
    # Here comes some validation for the request.
    #
    my $authorized_request = 0;
    #
    # First, check if the user requesting action is an admin
    if ($self->{ users }->is_admin_with_session($nick, $mask))
    {
        $log->info("User $nick is an administrator, will accept request to aop $subcmd $target_nick on $channel...");
        $authorized_request = 1;

    } else {
        # OK the user was not an admin, so what lvl is it? 
        $source_nickinfo = $self->__get_info_about_nick($nick, $channel);
        $log->debug(Dumper(%{$source_nickinfo}));

        my $slev = $$source_nickinfo{$nick}{$lvl} ||0;
        my $tlev = $$target_nickinfo{$target_nick}{$lvl} ||0;


        # If the source lvl (the lvl of requestor) is less than requested lvl, or less
        # than that of target, then reject this request...
        if ($slev < $lvl || $slev < $tlev)
        {
            return "msg $target $nick, sorry, but you don't have enough lvl to do that";
        } elsif ((not $$target_nickinfo{ $target_nick }) 
            and ($subcmd eq 'modify')) {
            # here's the check to see if you try to modify nonexistant nick for channel.
            return "msg $target $nick, $nick is not in the list for $channel...";
        }
    }

    # OK so here perform action!!
    if ($authorized_request == 1)
    {
        my $q;
        $lvl||=0;
        for ($subcmd)
        {
              when ('add') { $q = 'INSERT INTO aops (lvl, nick, channel) VALUES (?,?,?)' }
              when ('del') { $q = 'DELETE FROM aops WHERE -1 != ? AND nick = ? AND channel = ?' }
           when ('modify') { $q = 'UPDATE aops set lvl = ? WHERE nick = ? AND channel = ?' }
        }
        
        my $dbh = $self->dbh();
        my $sth = $dbh->prepare($q);

        if($sth->execute($lvl, $target_nick, $channel))
        {
            return "msg $target, OK $nick, I did $subcmd with $target_nick";
        } else {
            return "msg $target $nick: Unable to comply:" . (split("\n", $dbh->errstr))[0];
        }


    }


    return ;

}

sub __get_info_about_nick
{
    my $self = shift;
    my $nick = shift;
    my $channel= shift;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare(qq{ 
         SELECT nick,
                lvl,
                mask
           FROM aop_sessions
          WHERE nick = ? 
            AND channel = ?
    });

    $sth->execute($nick, $channel);

    return $sth->fetchall_hashref(qw/nick/);

}

1;
