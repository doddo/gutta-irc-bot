# Gutta the Irssi bot

Gutta is a modular IRC bot with powerful plugin interface and a small footprint.

## Install

Install perl and all required modules.

Then it is ready to go.



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


### Plugins

Gutta works with plugins, who recieves messages parsed by the Gutta::AbstractionLayer

The plugins are expected to return a conventional irc message and supports a multitude of options.



#### Writing Plugins'

Writing plugins for Gutta is easy.

Put them in the Gutta::Plugins folder, name them
Gutta::Plugins::Foo, and inherit Gutta::Plugin.


Here is the ~~hello world~~ Gutta::Plugins::Slap plugin:

```
package Gutta::Plugins::Slap;
# can slap with this one

use parent Gutta::Plugin;

sub slap
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    
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
