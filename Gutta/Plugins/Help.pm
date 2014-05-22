package Gutta::Plugins::Help;
# can help with this one

use Pod::Usage;
require Pod::Select;
use Data::Dumper;
use parent Gutta::Plugin;
use strict;
use warnings;

=head1 NAME

Gutta::Plugins::Help

=head1 SYNOPSIS

Provides Help for Gutta irc bot

=head1 DESCRIPTION

Provide support for help messages for the different plugins.

=head1 help

List a help message with support for additional SUBTOPIC

=cut

my $log;


sub help
{
    my $self = shift;
    my $server = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;
    my $rest_of_msg = shift;
    

    my $file_to_check;
    my $commands = $self->{ context }->get_plugin_commands();
    my @responses;

    # they need someonw to help
    #return unless $rest_of_msg;
    if (! $rest_of_msg)
    {
        # HERE IS WHAT HAPPENS IF THERE IS A NO HELP LIKE
        # THERE SHOULD BE TOC HERE
        @responses = (
            "msg $target Gutta Help Centre, can help with following topics:",
            "msg $target " . join("  ", keys %{$commands}),
        );
    } else {

        # Check if there are some plugin which *should* have this requested help.
        my ($command, @subcmds) = split(/\s+/, $rest_of_msg);

        if ($$commands{$command})
        {
            
            my @topics; #the help topics to select.
            # GET THE plugin_name from the command.
            # TODO I bet there is a better way to do this ;)
            $file_to_check = join('/', split(/::/, $$commands{$command}->{'plugin_name'}));
            $file_to_check.='.pm' ;
            $log->debug( "OK there *shpould* be help here, in $file_to_check maybe\n");

            my $helpmsg;

            # I have to fool pod2usage into thinking that 'HELPMSG_FILEHANDLE'
            # is actually a file but it is a variable: "$helpmsg".
            open( HELPVAR, '>', \$helpmsg);
           
            my $filehandle = \*HELPVAR;

            # OK is there an interest in the subtopics?
            if (@subcmds)
            {
                # escape all the regexes.
                my @escaped = map { quotemeta $_ } @subcmds;

                # then construct the string to be used.
                push @topics, join('/', quotemeta $command, @escaped, '!.+');
            } else {
                 # OK avoid help to traverse into subdirs /BY DEFAULT
                 # http://search.cpan.org/~marekr/Pod-Parser-1.62/lib/Pod/Select.pm
                push @topics,  "$command/!.+";
            }
        
            $log->debug("comprising help msg of " . Dumper(@topics));

            pod2usage( -verbose => 99,
                      -sections =>  [  @topics  ],
                       -message => "HELP FOR $rest_of_msg",
                         -input => $file_to_check,
                        -output => $filehandle,
                       -exitval => 'NOEXIT');

            close (HELPVAR), # Close this file handle.

            $helpmsg ||= "No help found for: $rest_of_msg\n";

            @responses =  map { "msg $target $_" } split("\n", $helpmsg);

        } else {
            # HERE IS WHAT HAPPENS IF THERE IS HELP REQUESTED, BUT OF UNKNOWN TOPIC
            # IE NO HELP TO BE HAD :(
            push @responses, "No plugin registered the functionality $command...";

        }
    }

    return @responses;
}

sub _initialise
{
    # called when plugin is istansiated
    my $self = shift;
    # The logger
    $log = Log::Log4perl->get_logger(__PACKAGE__);
}


sub _commands
{
    my $self = shift;
    # override this in plugin to set custom triggers
    #
    # The dispatch table for "triggers" which will be triggered
    # when one of them matches the IRC message.
    return {

        "help" => sub { $self->help(@_) },

    }
}
1;
