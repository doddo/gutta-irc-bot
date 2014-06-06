# Gutta the IRC bot

Gutta is a modular IRC bot with powerful plugin interface and a small footprint.


## Standalone mode

run

```bash
./gutta-standalone.pl --server irc.example.com --nick gutta --channel \#farmen --channel \#channel2
```

then (in the future)

interface with gutta with guttacli (or through plugins)


## Plugins

Gutta works with plugins, who recieves messages parsed by the Gutta::AbstractionLayer

The plugins are expected to return a conventional irc message and supports a multitude of options.

### Available plugins:

| Name  | Desc |
|  Gutta::Plugins::Auth | Support for running administrative commands etc |
|  Gutta::Plugins::DO | Make bot run any irc command |
|  Gutta::Plugins::Help | Provide help messages |
|  Gutta::Plugins::Ibood | Does something with Ibood |
|  Gutta::Plugins::Jira | Integrating with atlassian Jira |
|  Gutta::Plugins::Karma | Managing karma |
|  Gutta::Plugins::Nagios | Integrate with Nagios API for sending alarms |
|  Gutta::Plugins::Slap | Slap with bot |

### Writing Plugins

Writing plugins for Gutta is both easy and fun.

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
     
    # Plugin regurns one or more strings with IRC commands.
    return "msg $target me slaps $rest_of_msg  around a bit with a large trout.";
}


sub _commands
{
    my $self = shift;
    # Commands are privmsg:s starting with the customizable cmdprefix
    # which is either <bot nick>:<command> or simply !<command>.
    # What command to trigger, and a sub to handle the message is required like this:
    return {

        "slap" => sub { $self->slap(@_) },

    }
}
1;

```

## Install

Install perl and all required modules.

Then it is ready to go.

This version of Gutta requires at least perl 5.10.

### For ubuntu mint debian etc

```bash
 sudo apt-get install libdbi-perl \
	              libcrypt-passwdmd5-perl \
                      libclass-std-storable-perl \
                      libclass-dbi-sqlite-perl \
                      liblog-log4perl-perl \
                      libswitch-perl \
                      libdatetime-perl \
                      libdatetime-format-strptime-perl \
                      libdatetime-perl \
                      libhtml-strip-perl \
                      libxml-feedpp-perl \
                      libjson-perl
```

### For Fedora and similar

```bash
 sudo  yum  install   'perl(Crypt::PasswdMD5)'  \
                      'perl(Data::Dumper)'  \
                      'perl(DateTime)' \
                      'perl(DateTime::Format::Strptime)' \
                      'perl(DBI)' \
                      'perl(File::Basename)' \
                      'perl(Getopt::Long)' \
                      'perl(HTML::Strip)' \
                      'perl(HTML::TokeParser)' \
                      'perl(IO::Socket)' \
                      'perl(JSON)' \
                      'perl(Log::Log4perl)' \
                      'perl(LWP::Simple)' \
                      'perl(LWP::UserAgent)' \
                      'perl(MIME::Base64)' \
                      'perl(Pod::Usage)' \
                      'perl(Storable)' \
                      'perl(Switch)' \
                      'perl(Thread::Queue)' \
                      'perl(threads)' \
                      'perl(threads::shared)' \
                      'perl(XML::FeedPP)' 
```

