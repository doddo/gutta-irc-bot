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

  !op [ --channel C ] [ --nick N ]

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

    # OK get some settings from plugin...

    # 1. Is a valid session required for op (or is hostmask OK)
    #    Default to just op:ing if hostmask / nick matches.
    $self->{ login4op } = $self->get_config('login4op')||0; 
    
    # 2. What is the treshold for a user to be op:ped (0-100)
    #    Defaults to 1.
    $self->{ optreshold } = $self->get_config('optreshold')||1;
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
    my $nick = shift;
    my $mask  = shift;
    my $channel = shift;

    # they need someonw to aop
    $log->debug("In to $channel joins $nick with $mask. Handling this ...");

    # First check if there's a need to login for the $users to be op:ed, and if so,
    # is the user logged in?
    if ($self->{ login4op } and not $self->{ auth }->has_session($nick, $mask))
    {
        $log->debug("there was nothing to be done for $nick ...");
        return;
    }

    # Second check is if there is something about this user for the channel
    #
    my $nickdata = $self->__get_info_about_nick($nick, $channel);
    if ($$nickdata{$nick})
    {
        if ($$nickdata{$nick}{lvl} >= $self->{ optreshold })
        {
            if ($$nickdata{$nick}{mask} eq $mask)
            {
                $log->info("OP:ing $nick on $channel");
                return "mode $channel +o $nick"
            } else {
                $log->info("Would've OP:ped $nick on $channel, except that current mask '$mask', does not match mask from last identify:'$$nickdata{$nick}{mask}'");
            }
        }
    }

    # if we get here, then there's nothing to be done for $nick.
    return;
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
    my $target_n_or_c;

    # Possble subcmd...
    if ($rest_of_msg)
    {
        ($subcmd, @rest_of_msg) = split(' ',$rest_of_msg);
    }

    # OK do they want OP?
    if ($cmd eq 'op')
    {
        push @responses, $self->__handle_op($nick, $mask, $target, @rest_of_msg);
    } elsif ($cmd eq 'aop'){
        if ($subcmd ~~ ['add', 'del', 'modify'])
        {
            push @responses, 
                      $self->__nickmod($subcmd, $nick, $mask, $target, @rest_of_msg);
        } elsif ($subcmd eq 'list'){
             
            my $channel;
            if (@rest_of_msg)
            {
                $target_n_or_c = shift(@rest_of_msg)||undef;
            }

            if ($target_n_or_c and $target_n_or_c =~ m/^#/){
                $channel = $target_n_or_c;
            } elsif ($target =~ m/^#/){
                $channel = $target;
            } else {
               return "msg $target invalid channel supplied...";
            }
        
            my $nicklist = $self->__listaops($channel);

            if ($nicklist)
            {
                push @responses, "msg $target LIST FOR $channel:";

                # Sort by lvl here.
                my @keys = sort { $nicklist->{$b}->{ lvl } <=> 
                                  $nicklist->{$a}->{ lvl } } keys(%$nicklist);

                foreach my $n (@{$nicklist}{@keys})
                {
                    push @responses, sprintf "msg %s %-15s %-3i", $target, $$n{nick}, $$n{lvl};
                }
            }
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
    my @args = @_;


    # Parse options...
    my $target_channel;
    my $target_nick;

    GetOptionsFromArray(\@args,
          'channel=s' => \$target_channel,
             'nick=s' => \$target_nick)
    or return "msg $target invalid options supplied";

    unless ($target_nick)
    {
        $log->debug("Unspecified target to nick for OP cmd, assuming caller $nick");
        $target_nick = $nick;
    }

    my $target_channel = shift;
    unless ($target_channel)
    {
        $log->debug("Unspecified channel to OP $nick on, assuming origin $target");
        $target_channel = $target;
    }

    if ($target_channel !~ /^#/)
    {
        return "msg $target sorry but missing valid channel";
    }

    my $nickdata = $self->__get_info_about_nick($nick, $target_channel);

    $log->info("got OP request from $nick for $target_nick on $target_channel. Processing...");

    if ($self->{ auth }->has_session($nick, $mask))
    {
        if ($$nickdata{$nick}{lvl} >= $self->{ optreshold })
        {
            if ($$nickdata{$nick}{mask} eq $mask)
            {
                $log->info("OP:ing $target_nick on $target_channel");
                return "mode $target_channel +o $target_nick"
            } else {
                $log->info("Would've OP:ped $target_nick on $target_channel,  except that current mask '$mask', does not match mask from last identify:'$$nickdata{$target_nick}{mask}'");
                return "msg $target please re-identify first ...";
            }
        }
    } else {
        return "msg $target $nick, please identify yourself, and I see what I can do.";
    }
    return;
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
    or return "msg $target invalid options supplied";

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

        my $slev = $$source_nickinfo{$nick}{lvl}||0;
        my $tlev = $$target_nickinfo{$target_nick}{lvl}||0;


        # If the source lvl (the lvl of requestor) is less than requested lvl, or less
        # than that of target, then reject this request...
        if ($slev <= $lvl || $slev <= $tlev)
        {
            $log->info("rejected try to $subcmd $target_nick($tlev) by $nick($slev) to $lvl on $channel");
            return "msg $target $nick, sorry, but you don't have enough lvl to do that";
        } elsif ((not $$target_nickinfo{ $target_nick }) 
            and ($subcmd eq 'modify')) {
            # here's the check to see if you try to modify nonexistant nick for channel.
            return "msg $target $nick, $nick is not in the list for $channel...";
        }
        $authorized_request = 1;
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

sub __listaops
{
    my $self = shift;
    my $channel = shift;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare(qq{
         SELECT nick,
                lvl
           FROM aops
          WHERE channel = ?
       ORDER BY lvl DESC
    });

    $sth->execute($channel);

    return $sth->fetchall_hashref(qw/nick/);
}

1;
