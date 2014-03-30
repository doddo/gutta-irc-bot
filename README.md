# Gutta the IRC bot

Gutta is a modular IRC bot with powerful plugin interface and a small footprint.

## Install

Install perl and all required modules.

Then it is ready to go.

This version of Gutta requires at least perl 5.16, (but it's not too much work making it run on older perl 5.10 too so maybe in the future it will)


### Standalone mode

run

```bash
./gutta-standalone.pl --server irc.example.com --nick gutta --channel \#farmen --channel \#channel2
```

then (in the future)

interface with gutta with guttacli (or through plugins)

### Run inside of Irssi

Put the whole thing under -> ~/.irssi/scripts

do /load gutta.pl

and then its good to go.


## Plugins

Gutta works with plugins, who recieves messages parsed by the Gutta::AbstractionLayer

The plugins are expected to return a conventional irc message and supports a multitude of options.



### Writing Plugins

Writing plugins for Gutta is easy.

Put them in the Gutta::Plugins folder, name them
Gutta::Plugins::Foo, and inherit Gutta::Plugin.


Here is the ~~hello world~~ Gutta::Plugins::Slap plugin:

```perl
package Gutta::Plugins::Slap;
# can slap with this one

use parent Gutta::Plugin;

sub slap
{
    my $self = shift;          # ref to class
    my $server = shift;        # the irc server of msg origin
    my $msg = shift;           # the message
    my $nick = shift;          # the nick who sent it
    my $mask = shift;          # the nicks hostmask/ip
    my $target = shift;        # target in what channel/from what nick did the msg originate
    my $rest_of_msg = shift;   # the message with cmdprefix stripped.
    
    # they need someonw to slap
    return unless $rest_of_msg;

    return "msg $target \001ACTION  slaps $rest_of_msg  around a bit with a large trout.";
}


sub _commands
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    return {

        "slap" => sub { $self->slap(@_) },

    }
}
1;


```
