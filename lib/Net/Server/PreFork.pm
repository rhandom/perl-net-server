# -*- perl -*-
#
#  Net::Server::PreFork - Net::Server personality
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
################################################################

package Net::Server::PreFork;

use strict;
use vars qw($VERSION @ISA $LOCK_EX $LOCK_UN);
use POSIX qw(WNOHANG);
use Net::Server::PreForkSimple;
use Net::Server::SIG qw(register_sig check_sigs);
use IO::Select ();

$VERSION = $Net::Server::VERSION; # done until separated

### fall back to parent methods
@ISA = qw(Net::Server::PreForkSimple);


### override-able options for this package
sub options {
  my $self = shift;
  my $prop = $self->{server};
  my $ref  = shift;

  $self->SUPER::options($ref);

  foreach ( qw(min_servers
               min_spare_servers max_spare_servers
               spare_servers
               check_for_waiting
               ) ){
    $prop->{$_} = undef unless exists $prop->{$_};
    $ref->{$_} = \$prop->{$_};
  }

}

### make sure some defaults are set
sub post_configure {
  my $self = shift;
  my $prop = $self->{server};

  ### legacy check
  if( defined($prop->{spare_servers}) ){
    die "The Net::Server::PreFork argument \"spare_servers\" has been
deprecated as of version '0.75' in order to implement greater child
control.  The new arguments to take \"spare_servers\" place are
\"min_spare_servers\" and \"max_spare_servers\".  The defaults are 5
and 15 respectively.  Please remove \"spare_servers\" from your
argument list.  See the Perldoc Net::Server::PreFork for more
information.
";
  }

  ### let the parent do the rest
  ### must do this first so that ppid reflects backgrounded process
  $self->SUPER::post_configure;

  ### some default values to check for
  my $d = {min_servers       => 5,    # min num of servers to always have running
           min_spare_servers => 2,    # min num of servers just sitting there
           max_spare_servers => 10,   # max num of servers just sitting there
           check_for_waiting => 10,   # how often to see if children laying around
           };
  foreach (keys %$d){
    $prop->{$_} = $d->{$_}
    unless defined($prop->{$_}) && $prop->{$_} =~ /^\d+$/;
  }

  if( $prop->{min_spare_servers} > $prop->{max_spare_servers} ){
    $self->fatal("Error: \"min_spare_servers\" must be less than "
                 ."\"max_spare_servers\"");
  }

  if( $prop->{min_spare_servers} > $prop->{min_servers} ){
    $self->fatal("Error: \"min_spare_servers\" must be less than "
                 ."\"min_servers\"");
  }

  if( $prop->{max_spare_servers} >= $prop->{max_servers} ){
    $self->fatal("Error: \"max_spare_servers\" must be less than "
                 ."\"max_servers\"");
  }

}


### prepare for connections
sub loop {
  my $self = shift;
  my $prop = $self->{server};

  ### get ready for child->parent communication
  pipe(_READ,_WRITE);
  $prop->{_READ}  = *_READ;
  $prop->{_WRITE} = *_WRITE;

  ### get ready for children
  $prop->{children} = {};

  $self->log(3,"Beginning prefork ($prop->{min_servers} processes)\n");

  ### keep track of the status
  $prop->{tally} = {time       => time(),
                    waiting    => 0,
                    processing => 0,
                    dequeue    => 0};

  ### start up the children
  $self->run_n_children( $prop->{min_servers} );

  ### finish the parent routines
  $self->run_parent;
  
}

### sub to kill of a specified number of children
sub kill_n_children {
  my $self = shift;
  my $prop = $self->{server};
  my $n    = shift;
  return unless $n > 0;

  return unless time() - $prop->{last_kill} > 10;
  $prop->{last_kill} = time();

  $self->log(3,"Killing \"$n\" children");

  foreach (keys %{ $prop->{children} }){
    next unless $prop->{children}->{$_} eq 'waiting';
    if( ! kill('HUP',$_) ){
      delete $prop->{children}->{$_};
      next;
    }
    last if --$n <= 0;
  }
}

### subroutine to start up a specified number of children
sub run_n_children {
  my $self  = shift;
  my $prop  = $self->{server};
  my $n     = shift;
  return unless $n > 0;

  $self->log(3,"Starting \"$n\" children");
  $prop->{last_start} = time();
  
  for( 1..$n ){
    my $pid = fork;

    ### trouble
    if( not defined $pid ){
      $self->fatal("Bad fork [$!]");

    ### parent
    }elsif( $pid ){
      $prop->{children}->{$pid} = 'waiting';
      $prop->{tally}->{waiting} ++;

    ### child
    }else{
      $self->run_child;

    }
  }
}


### child process which will accept on the port
sub run_child {
  my $self = shift;
  my $prop = $self->{server};

  ### restore sigs (turn off warnings during)
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT}
    = $SIG{CHLD} = $SIG{PIPE} = 'DEFAULT';

  $self->log(4,"Child Preforked ($$)\n");

  delete $prop->{$_} foreach qw(children tally last_start last_process);

  $self->child_init_hook;

  ### let the parent shut me down
  $prop->{connected} = 0;
  $prop->{SigHUPed}  = 0;
  $SIG{HUP} = sub {
    unless( $prop->{connected} ){
      exit;
    }
    $prop->{SigHUPed} = 1;
  };

  ### accept connections
  while( $self->accept() ){
    
    $prop->{connected} = 1;
    print _WRITE "$$ processing\n";

    $self->run_client_connection;

    last if $self->done;

    $prop->{connected} = 0;
    print _WRITE "$$ waiting\n";

  }
  
  $self->child_finish_hook;

  print _WRITE "$$ exiting\n";
  exit;

}


### now the parent will wait for the kids
sub run_parent {
  my $self=shift;
  my $prop = $self->{server};

  $self->log(4,"Parent ready for children.\n");
  
  ### prepare to read from children
  local *_READ = $prop->{_READ};
  _READ->autoflush(1);

  ### allow for writing to _READ
  local *_WRITE = $prop->{_WRITE};
  _WRITE->autoflush(1);

  ### set some waypoints
  $prop->{last_checked_for_dead}
  = $prop->{last_checked_for_waiting}
  = $prop->{last_checked_for_dequeue}
  = $prop->{last_process}
  = $prop->{last_kill}
  = time();

  ### register some of the signals for safe handling
  register_sig(PIPE => 'IGNORE',
               INT  => sub { $self->server_close() },
               TERM => sub { $self->server_close() },
               QUIT => sub { $self->server_close() },
               HUP  => sub { $self->sig_hup() },
               CHLD => sub {
                 while ( defined(my $chld = waitpid(-1, WNOHANG)) ){
                   last unless $chld > 0;
                   delete $prop->{children}->{$chld};
                 }
               },
### uncomment this area to allow SIG USR1 to give some runtime debugging               
#               USR1 => sub {
#                 require "Data/Dumper.pm";
#                 print Data::Dumper::Dumper($self);
#               },
               );

  ### need a selection handle
  my $select = IO::Select->new();
  $select->add(\*_READ);

  ### loop on reading info from the children
  while( 1 ){

    ### Wait to read.
    ## Normally it is not good to do selects with
    ## getline or <$fh> but this is controlled output
    ## where everything that comes through came from us.
    my @fh = $select->can_read(10);
    if( &check_sigs() ){
      last if $prop->{_HUP};
    }
    if( ! @fh ){
      $self->coordinate_children();
      next;
    }

    ### get the filehandle
    my $fh = shift(@fh);
    next unless defined $fh;
    
    ### read a line
    my $line = <$fh>;
    next if not defined $line;

    ### optional test by user hook
    last if $self->parent_read_hook($line);

    ### child should say "$pid status\n"
    next unless $line =~ /^(\d+)\ +(waiting|processing|dequeue|exiting)$/;
    my ($pid,$status) = ($1,$2);

    ### record the status
    $prop->{children}->{$pid} = $status;
    if( $status eq 'processing' ){
      $prop->{tally}->{processing} ++;
      $prop->{tally}->{waiting} --;
      $prop->{last_process} = time();
    }elsif( $status eq 'waiting' ){
      $prop->{tally}->{processing} --;
      $prop->{tally}->{waiting} ++;
    }elsif( $status eq 'exiting' ){
      $prop->{tally}->{processing} --;
      delete $prop->{children}->{$pid};
    }

    ### check up on the children
    $self->coordinate_children();

  }

  ### allow fall back to main run method
}


### routine to determine if more children need to be started or stopped
sub coordinate_children {
  my $self = shift;
  my $prop = $self->{server};
  my $time = time();

  ### re-tally the possible types (only once a minute)
  ### this might not be even necessary but is a nice sanity check
  if( $time - $prop->{tally}->{time} > 6 ){
    my $w = $prop->{tally}->{waiting};
    my $p = $prop->{tally}->{processing};
    $prop->{tally} = {time       => $time,
                      waiting    => 0,
                      processing => 0,
                      dequeue    => 0};
    foreach (values %{ $prop->{children} }){
      $prop->{tally}->{$_} ++;
    }
    $w -= $prop->{tally}->{waiting};
    $p -= $prop->{tally}->{processing};
    $self->log(3,"Processing diff ($p), Waiting diff ($w)")
      if $p || $w;
  }

  my $total = $prop->{tally}->{waiting} + $prop->{tally}->{processing};

  ### need more min_servers
  if( $total < $prop->{min_servers} ){
    $self->run_n_children( $prop->{min_servers} - $total );
    
  ### need more min_spare_servers (up to max_servers)
  }elsif( $prop->{tally}->{waiting} < $prop->{min_spare_servers} 
          && $total < $prop->{max_servers} ){
    my $n1 = $prop->{min_spare_servers} - $prop->{tally}->{waiting};
    my $n2 = $prop->{max_servers} - $total;
    $self->run_n_children( ($n2 > $n1) ? $n1 : $n2 );

  }


  ### check to see if we should kill off some children
  if( $time - $prop->{last_checked_for_waiting} > $prop->{check_for_waiting} ){
    $prop->{last_checked_for_waiting} = $time;

    ### need fewer max_spare_servers (down to min_servers)
    if( $prop->{tally}->{waiting} > $prop->{max_spare_servers}
        && $total > $prop->{min_servers} ){

      ### see if we haven't started any in the last ten seconds
      if( $time - $prop->{last_start} > 10 ){
        my $n1 = $prop->{tally}->{waiting} - $prop->{max_spare_servers};
        my $n2 = $total - $prop->{min_servers};
        $self->kill_n_children( ($n2 > $n1) ? $n1 : $n2 );
      }      

    ### how did this happen?
    }elsif( $total > $prop->{max_servers} ){
      $self->kill_n_children( $total - $prop->{max_servers} );
      
    }
  }
  
  ### periodically make sure children are alive
  if( $time - $prop->{last_checked_for_dead} > $prop->{check_for_dead} ){
    $prop->{last_checked_for_dead} = $time;
    foreach (keys %{ $prop->{children} }){
      ### see if the child can be killed
      kill(0,$_) or delete $prop->{children}->{$_};
    }
  }

  ### take us down to min if we haven't had a request in a while
  if( $time - $prop->{last_process} > 30 && $prop->{tally}->{waiting} > $prop->{min_spare_servers} ){
    my $n1 = $prop->{tally}->{waiting} - $prop->{min_spare_servers};
    my $n2 = $total - $prop->{min_servers};
    $self->kill_n_children( ($n2 > $n1) ? $n1 : $n2 );
  }

  ### periodically check to see if we should clear the queue
  if( defined $prop->{check_for_dequeue} ){
    if( $time - $prop->{last_checked_for_dequeue} > $prop->{check_for_dequeue} ){
      $prop->{last_checked_for_dequeue} = $time;
      if( defined($prop->{max_dequeue})
          && $prop->{tally}->{dequeue} < $prop->{max_dequeue} ){
        $self->run_dequeue();
      }
    }
  }

}


1;

__END__

=head1 NAME

Net::Server::PreFork - Net::Server personality

=head1 SYNOPSIS

  use Net::Server::PreFork;
  @ISA = qw(Net::Server::PreFork);

  sub process_request {
     #...code...
  }

  __PACKAGE__->run();

=head1 DESCRIPTION

Please read the pod on Net::Server and Net::Server::PreForkSimple
first.  This module is a personality, or extension, or sub class,
of the Net::Server::PreForkSimple class which is a sub class of
Net::Server.  See L<Net::Server::PreForkSimple>.

This personality binds to one or more ports and then forks
C<min_servers> child process.  The server will make sure
that at any given time there are C<min_spare_servers> available
to receive a client request, up to C<max_servers>.  Each of
these children will process up to C<max_requests> client
connections.  This type is good for a heavily hit site, and
should scale well for most applications.  (Multi port accept
is accomplished using flock to serialize the children).

=head1 SAMPLE CODE

Please see the sample listed in Net::Server.

=head1 COMMAND LINE ARGUMENTS

In addition to the command line arguments of the Net::Server
base class and the Net::Server::PreForkSimple parent class,
Net::Server::PreFork contains several other configurable
parameters.  You really should also see
L<Net::Server::PreForkSimple>.

  Key               Value                   Default
  min_servers       \d+                     5
  min_spare_servers \d+                     2
  max_spare_servers \d+                     10
  max_servers       \d+                     50
  max_requests      \d+                     1000

  serialize         (flock|semaphore|pipe)  undef
  # serialize defaults to flock on multi_port or on Solaris
  lock_file         "filename"              POSIX::tmpnam
                                            
  check_for_dead    \d+                     30
  check_for_waiting \d+                     10

  max_dequeue       \d+                     undef
  check_for_dequeue \d+                     undef

=over 4

=item min_servers

The minimum number of servers to keep running.

=item min_spare_servers

The minimum number of servers to have waiting for requests.
Minimum and maximum numbers should not be set to close to
each other or the server will fork and kill children too
often.

=item max_spare_servers

The maximum number of servers to have waiting for requests.
See I<min_spare_servers>.

=item max_servers

The maximum number of child servers to start.  This does not
apply to dequeue processes.

=item check_for_waiting

Seconds to wait before checking to see if we can kill
off some waiting servers.

=back

=head1 CONFIGURATION FILE

C<Net::Server::PreFork> allows for the use of a
configuration file to read in server parameters.  The format
of this conf file is simple key value pairs.  Comments and
white space are ignored.

  #-------------- file test.conf --------------

  ### server information
  min_servers   20
  max_servers   80
  min_spare_servers 10
  min_spare_servers 15

  max_requests  1000

  ### user and group to become
  user        somebody
  group       everybody

  ### logging ?
  log_file    /var/log/server.log
  log_level   3
  pid_file    /tmp/server.pid

  ### access control
  allow       .+\.(net|com)
  allow       domain\.com
  deny        a.+

  ### background the process?
  background  1

  ### ports to bind
  host        127.0.0.1
  port        localhost:20204
  port        20205

  ### reverse lookups ?
  # reverse_lookups on
 
  #-------------- file test.conf --------------

=head1 PROCESS FLOW

Process flow follows Net::Server until the loop phase.  At
this point C<min_servers> are forked and wait for
connections.  When a child accepts a connection, finishs
processing a client, or exits, it relays that information to
the parent, which keeps track and makes sure there are
enough children to fulfill C<min_servers>, C<min_spare_servers>,
C<max_spare_servers>, and C<max_servers>.

=head1 HOOKS

There is one additional hook in the PreFork server.
See L<Net::Server::PreForkSimple> for other hooks.

=over 4

=item C<$self-E<gt>parent_read_hook()>

This hook occurs any time that the parent reads information
from the child.  The line from the child is sent as an
argument.

=back

=head1 TO DO

See L<Net::Server>

=head1 AUTHOR

Paul T. Seamons paul@seamons.com

=head1 THANKS

See L<Net::Server>

=head1 SEE ALSO

Please see also
L<Net::Server::Fork>,
L<Net::Server::INET>,
L<Net::Server::PreForkSimple>,
L<Net::Server::MultiType>,
L<Net::Server::Single>
L<Net::Server::SIG>
L<Net::Server::Daemonize>
L<Net::Server::Proto>

=cut

