# -*- perl -*-
#
#  Net::Server::Daemonize - adpf - Daemonization utilities.
#  
#  $Id$
#  
#  Copyright (C) 2001, Paul T Seamons
#                      paul@seamons.com
#                      http://seamons.com/
#  
#  This package may be distributed under the terms of either the
#  GNU General Public License 
#    or the
#  Perl Artistic License
#
#  All rights reserved.
#  
#  Please read the perldoc Net::Server
#
################################################################

package Net::Server::Daemonize;

use strict;
use vars qw( @ISA @EXPORT_OK $VERSION );
use Exporter ();
use POSIX qw(SIGINT SIG_BLOCK SIG_UNBLOCK);

$VERSION = "0.02";


@EXPORT_OK = qw(check_pid_file
                create_pid_file
                daemonize
                safe_fork
                );
@ISA = qw(Exporter);

### check for existance of pid_file
### if the file exists, check for a running process
sub check_pid_file ($) {
  my $pid_file = shift;

  ### untaint the filename (doesn't mean that
  ### somebody couldn't pass /etc/passwd and cause
  ### a lot of trouble)
  unless( $pid_file =~ m|^([\w\.\-/]+)$| ){
    die "Unsecure filename \"$prop->{pid_file}\"\n";
  }
  $pid_file = $1;

  ### no pid_file = return success
  return 1 unless -e $pid_file;

  ### get the currently listed pid
  if( ! open(_PID,$pid_file) ){
    die "Couldn't open existant pid_file \"$pid_file\" [$!]\n";
  }
  my $current_pid = <_PID>;
  close _PID;
  chomp($current_pid);


  my $exists = undef;


  ### try a proc file system
  if( -d '/proc' && opendir(_DH,'/proc') ){
    
    while ( defined(my $pid = readdir(_DH)) ){
      if( $pid eq $current_pid ){
        $exists = 1;
        last;
      }
    }
    
  ### try ps
  #}elsif( -x '/bin/ps' ){ # not as portable
  }elsif( `ps h -p $$` ){ # can I play ps on myself ?
    $exists = `ps h -p $current_pid`;
    
  }

  ### running process exists, ouch
  if( $exists ){
    die "pid_file already exists for running process ($current_pid)... aborting\n";
    
  }

  ### remove the pid_file
  warn "pid_file \"$pid_file\" already exists.  Overwriting.\n";
  unlink $pid_file;

  return 1;
}

### actually create the pid_file, calls check_pid_file
### before proceeding
sub create_pid_file ($) {
  my $pid_file = shift;

  ### untaint the filename (doesn't mean that
  ### somebody couldn't pass /etc/passwd and cause
  ### a lot of trouble)
  unless( $pid_file =~ m|^([\w\.\-/]+)$| ){
    die "Unsecure filename \"$prop->{pid_file}\"\n";
  }
  $pid_file = $1;

  ### see if the pid_file is already there
  check_pid_file( $pid_file );

  
  if( ! open(PID, ">$prop->{pid_file}") ){
    die "Couldn't open pid file \"$prop->{pid_file}\" [$!].\n";
  }


  ### save out the pid and exit
  print PID "$$\n";
  close PID;

  return 1;
}

###----------------------------------------------------------------###

### routine to completely dissociate from
### terminal process.
sub daemonize ($$$) {
  my ($user, $group, $pid_file) = @_;

  check_pid_file( $pid_file );

  set_user($user, $group);

  my $pid = safe_fork();

  ### parent process should do the pid file and exit
  if( $pid ){

    # Record child pid for killing later
    create_pid_file( $pid_file );

    # Kill the parent process
    $pid && exit(0);


  ### child should close all input/output and separate
  ### from the parent process group
  }else{
  
    open STDIN,  '</dev/null' or die "Can't open STDIN from /dev/null: [$!]\n";
    open STDOUT, '>/dev/null' or die "Can't open STDOUT to /dev/null: [$!]\n";
    open STDERR, '>&STDOUT'   or die "Can't open STDERR to STDOUT: [$!]\n";

    ### Change to root dir to avoid locking a mounted file system
    chdir '/'                 or die "Can't chdir to \"/\": [$!]";

    ### Turn process into session leader, and ensure no controlling terminal
    POSIX::setsid();

    ### install a signal handler to make sure
    ### SIGINT's remove our pid_file
    $SIG{INT}  = sub { HUNTSMAN( $pid_file ); };
    return 1;

  }
}

sub set_user {
  my ($user, $group) = @_;
  my $UserId = getpwnam($user);
  my $GroupId = getgrnam($group);
  $> = $< = $UserId;
  $) = $( = $GroupId;
  POSIX::setuid $UserId;
  POSIX::setgid $GroupId;
  return 1;
}


sub safe_fork () {
  
  ### block signal for fork
  my $sigset = POSIX::SigSet->new(SIGINT);
  POSIX::sigprocmask(SIG_BLOCK, $sigset)
    or die "Can't block SIGINT for fork: [$!]\n";
  
  ### fork off a child
  my $pid = fork;
  unless( defined $pid ){
    die "Couldn't fork: [$!]\n";
  }

  ### make SIGINT kill us as it did before
  $SIG{INT} = 'DEFAULT';

  ### put back to normal
  POSIX::sigprocmask(SIG_UNBLOCK, $sigset)
    or die "Can't unblock SIGINT for fork: [$!]\n";

  return $pid;
}

sub HUNTSMAN {                      
  my ($path) = @_;
  unlink ($path);
  Unix::Syslog::syslog LOG_ERR, "Exiting on INT signal.";
  exit;                           # clean up with dignity
}




1;

__END__

=back

=head1 AUTHOR

(c) 2001 Jeremy Howard <j+daemonize@howard.fm>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=head1 SEE ALSO

L<Net::Daemon>, The Perl Cookbook Recipe 17.15.

=cut
