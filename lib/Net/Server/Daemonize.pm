# -*- perl -*-
#
#  Net::Server::Daemonize - bdpf - Daemonization utilities.
#  
#  $Id$
#  
#  Copyright (C) 2001, Jeremy Howard
#                      j+daemonize@howard.fm
#
#                      Paul T Seamons
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

$VERSION = "0.03";

@ISA = qw(Exporter);

@EXPORT_OK = qw(check_pid_file
                create_pid_file
                unlink_pid_file
                is_root_user
                get_uid get_gid
                set_uid set_gid
                set_user
                safe_fork
                daemonize
                );

###----------------------------------------------------------------###

### check for existance of pid_file
### if the file exists, check for a running process
sub check_pid_file ($) {
  my $pid_file = shift;

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
  # the ps command itself really isn't portable
  # this follows BSD syntax ps (BSD's and linux)
  # this will fail on Unix98 syntax ps (Solaris, etc)
  }elsif( `ps h o pid p $$` =~ /^\s*$$\s*$/ ){ # can I play ps on myself ?
    $exists = `ps h o pid p $current_pid`;
    
  }

  ### running process exists, ouch
  if( $exists ){
    
    if( $current_pid == $$ ){
      warn "Pid_file created by this same process. Doing nothing.\n";
      return 1;
    }else{
      die "Pid_file already exists for running process ($current_pid)... aborting\n";
    }    

  ### remove the pid_file
  }else{

    warn "Pid_file \"$pid_file\" already exists.  Overwriting!\n";
    unlink $pid_file || die "Couldn't remove pid_file \"$pid_file\" [$!]\n";
    return 1;

  }
}

### actually create the pid_file, calls check_pid_file
### before proceeding
sub create_pid_file ($) {
  my $pid_file = shift;

  ### see if the pid_file is already there
  check_pid_file( $pid_file );
  
  if( ! open(PID, ">$pid_file") ){
    die "Couldn't open pid file \"$pid_file\" [$!].\n";
  }

  ### save out the pid and exit
  print PID "$$\n";
  close PID;

  die "Pid_file \"$pid_file\" not created.\n" unless -e $pid_file;
  return 1;
}

### Allow for safe removal of the pid_file.
### Make sure this process owns it.
sub unlink_pid_file ($) {
  my $pid_file = shift;

  ### no pid_file = return success
  return 1 unless -e $pid_file;

  ### get the currently listed pid
  if( ! open(_PID,$pid_file) ){
    die "Couldn't open existant pid_file \"$pid_file\" [$!]\n";
  }
  my $current_pid = <_PID>;
  close _PID;
  chomp($current_pid);


  if( $current_pid == $$ ){
    unlink($pid_file) || die "Couldn't unlink pid_file \"$pid_file\" [$!]\n";
    return 1;

  }else{
    die "Process $$ doesn't own pid_file \"$pid_file\". Can't remove it.\n";
    
  }

}

###----------------------------------------------------------------###

sub is_root_user () {
  my $id = get_uid('root');
  return ( ! defined($id) || $< == $id || $> == $id );
}

### get the uid for the passed user
sub get_uid ($) {
  my $user = shift;
  my $uid  = undef;

  if( $user =~ /^\d+$/ ){
    $uid = $user;
  }else{
    $uid = getpwnam($user);
  }
  
  die "No such user \"$user\"\n" unless defined $uid;

  return $uid;
}

### get all of the gids that this group is (space delimited)
sub get_gid {
  my @gid  = ();

  foreach my $group ( split( /[, ]+/, join(" ",@_) ) ){
    if( $group =~ /^\d+$/ ){
      push @gid, $group;
    }else{
      my $id = getgrnam($group);
      die "No such group \"$group\"\n" unless defined $id;
      push @gid, $id;
    }
  }

  die "No group found in arguments.\n" unless @gid;

  return join(" ",$gid[0],@gid);
}

### change the process to run as this uid
sub set_uid {
  my $uid = get_uid( shift() );
  $< = $> = $uid;
  POSIX::setuid( $uid ) || die "Couldn't POSIX::setuid to \"$uid\" [$!]\n";
  return 1;
}

### change the process to run as this gid(s)
### multiple groups must be space or comma delimited
sub set_gid {
  my $gids = get_gid( @_ );
  my $gid  = (split(/\s+/,$gids))[0];
  $) = $gids;
  $( = $gid;
  POSIX::setgid( $gid ) || die "Couldn't POSIX::setgid to \"$gid\" [$!]\n";
  return 1;
}

### backward compatibility sub
sub set_user {
  my ($user, @group) = @_;
  set_uid( $user )  || return undef;
  set_gid( @group ) || return undef;
  return 1;
}

###----------------------------------------------------------------###

### routine to protect process during fork
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

### SIGINT routine that will remove the pid_file
sub HUNTSMAN {                      
  my ($path) = @_;
  unlink ($path);

  require "Unix/Syslog.pm";
  Unix::Syslog::syslog(Unix::Syslog::LOG_ERR(), "Exiting on INT signal.");

  exit;
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
