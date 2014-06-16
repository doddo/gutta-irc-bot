package Gutta::Constants;
use strict;
use warnings;
use Log::Log4perl;
use File::Basename;
use File::Spec::Functions;
use Cwd 'abs_path';


use base 'Exporter';

=head1 NAME

Gutta::Constants

=head1 SYNOPSIS

These constants are used by everyone (or will be)


=head1 DESCRIPTION

This is how gutta can find its datadirs etc


=cut

# The logger
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# Directories
use constant      GUTTADIR => dirname(abs_path(__FILE__));
use constant       BASEDIR => catdir(GUTTADIR, '..');
use constant       DATADIR => catdir(GUTTADIR, 'Data');
use constant     PLUGINDIR => catdir(GUTTADIR, 'Plugins');
use constant     CONFIGDIR => catdir(GUTTADIR, 'Config');

# Files
use constant        DBFILE => catdir(DATADIR, 'gutta.db');
use constant SESSIONDBFILE => catfile(DATADIR, 'session.db');
use constant  LOG4PERLCONF => catfile(CONFIGDIR, 'Log4perl.conf');

# Want to export directly, thats OK
our @EXPORT_OK = qw/GUTTADIR BASEDIR DATADIR PLUGINDIR CONFIGDIR 
                                            DBFILE SESSIONDBFILE LOG4PERLCONF/;

1;
