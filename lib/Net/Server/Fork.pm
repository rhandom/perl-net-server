# -*- perl -*-
#
#  Net::Server::Fork - Net::Server personality
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

package Net::Server::Fork;

use strict;
use vars qw($VERSION @ISA);
use Net::Server ();
use Net::Server::SIG qw(register_sig check_sigs);
use Socket qw(SO_TYPE SOL_SOCKET SOCK_DGRAM);
use POSIX qw(WNOHANG);

$VERSION = $Net::Server::VERSION; # done until separated

### fall back to parent methods
@ISA = qw(Net::Server);


### override-able options for this package
sub options {
  my $self = shift;
  my $prop = $self->{server};
  my $ref  = shift;

  $self->SUPER::options($ref);

  foreach ( qw(max_servers check_for_dead) ){
    $prop->{$_} = undef unless exists $prop->{$_};
    $ref->{$_} = \$prop->{$_};
  }
}

### make sure some defaults are set
sub post_configure {
  my $self = shift;
  my $prop = $self->{server};

  ### let the parent do the rest
  $self->SUPER::post_configure;

  ### what are the max number of processes
  $prop->{max_servers} = 256
    unless defined $prop->{max_servers};

  ### how often to see if children are alive
  ### only used when max_servers is reached
  $prop->{check_for_dead} = 60
    unless defined $prop->{check_for_dead};

  ### I need to know who is the parent
  $prop->{ppid} = $$;

  ### let the post bind set up a select handle for us
  $prop->{multi_port} = 1;

}


### loop, fork, and process connections
sub loop {
  my $self = shift;
  my $prop = $self->{server};

  ### get ready for children
  $prop->{children} = {};

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
               );

  ### this is the main loop
  while( 1 ){

    my $last_checked_for_dead = time();

    ### make sure we don't use too many processes
    while ((keys %{ $prop->{children} }) > $prop->{max_servers}){

      ### block for a moment (don't look too often)
      select(undef,undef,undef,5);
      &check_sigs();

      ### periodically see which children are alive
      my $time = time();
      if( $time - $last_checked_for_dead > $prop->{check_for_dead} ){
        $last_checked_for_dead = $time;
        foreach (keys %{ $prop->{children} }){
          ### see if the child can be killed
          kill(0,$_) or delete $prop->{children}->{$_};
        }
      }
    }

    
    ### try to call accept
    if( ! $self->accept() ){
      last if $prop->{_HUP};
      next;
    }
    
    ### fork a child so the parent can go back to listening
    my $pid = fork;
    
    ### trouble
    if( not defined $pid ){
      $self->log(1,"Bad fork [$!]");
      sleep(5);
      
    ### parent
    }elsif( $pid ){
      close($prop->{client}) if ! $prop->{udp_true};
      $prop->{children}->{$pid} = time;
      
    ### child
    }else{
      $self->run_client_connection;
      exit;
      
    }
    
  }

  ### fall back to the main run routine
}

### Net::Server::Fork's own accept method which
### takes advantage of safe signals
sub accept {
  my $self = shift;
  my $prop = $self->{server};

  ### block on trying to get a handle, timeout on 10 seconds
  my(@socks) = $prop->{select}->can_read(10);
  
  ### see if any sigs occured
  if( &check_sigs() ){
    return undef if $prop->{_HUP};
    return undef unless @socks; # don't continue unless we have a connection
  }

  ### choose one at random (probably only one)
  my $sock = $socks[rand @socks];
  return undef unless defined $sock;
  
  ### check if this is UDP
  if( SOCK_DGRAM == $sock->getsockopt(SOL_SOCKET,SO_TYPE) ){
    $prop->{udp_true} = 1;
    $prop->{client}   = $sock;
    $prop->{udp_true} = 1;
    $prop->{udp_peer} = $sock->recv($prop->{udp_data},
                                    $sock->NS_recv_len,
                                    $sock->NS_recv_flags);
    
  ### Receive a SOCK_STREAM (TCP or UNIX) packet
  }else{
    delete $prop->{udp_true};
    $prop->{client} = $sock->accept();
    return undef unless defined $prop->{client};
  }
}

### override a little to restore sigs
sub run_client_connection {
  my $self = shift;

  ### close the main sock, we still have
  ### the client handle, this will allow us
  ### to HUP the parent at any time
  $_ = undef foreach @{ $self->{server}->{sock} };

  ### restore sigs (for the child)
  $SIG{HUP} = $SIG{CHLD} = $SIG{PIPE}
     = $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = 'DEFAULT';

  $self->SUPER::run_client_connection;

}

### routine to shut down the server (and all forked children)
sub server_close {
  my $self = shift;
  my $prop = $self->{server};

  ### if a parent, fork off cleanup sub and close
  if( ! defined $prop->{ppid} || $prop->{ppid} == $$ ){

    $self->SUPER::server_close();

  ### if a child, signal the parent and close
  ### normally the child shouldn't, but if they do...
  }else{

    kill(2,$prop->{ppid});

  }
  
  exit;
}

1;

__END__

=head1 NAME

Net::Server::Fork - Net::Server personality

=head1 SYNOPSIS

  use Net::Server::Fork;
  @ISA = qw(Net::Server::Fork);

  sub process_request {
     #...code...
  }

  __PACKAGE__->run();

=head1 DESCRIPTION

Please read the pod on Net::Server first.  This module
is a personality, or extension, or sub class, of the
Net::Server module.

This personality binds to one or more ports and then waits
for a client connection.  When a connection is received,
the server forks a child.  The child handles the request
and then closes.

=head1 ARGUMENTS

=over 4

=item check_for_dead

Number of seconds to wait before looking for dead children.
This only takes place if the maximum number of child processes
(max_servers) has been reached.  Default is 60 seconds.

=item max_servers

The maximum number of children to fork.  The server will
not accept connections until there are free children. Default
is 256 children.

=back

=head1 CONFIGURATION FILE

See L<Net::Server>.

=head1 PROCESS FLOW

Process flow follows Net::Server until the post_accept phase.
At this point a child is forked.  The parent is immediately
able to wait for another request.  The child handles the 
request and then exits.

=head1 HOOKS

There are no additional hooks in Net::Server::Fork.

=head1 TO DO

See L<Net::Server>

=head1 FILES

  The following files are installed as part of this
  distribution.

  Net/Server.pm
  Net/Server/Fork.pm
  Net/Server/INET.pm
  Net/Server/MultiType.pm
  Net/Server/PreFork.pm
  Net/Server/Single.pm

=head1 AUTHOR

Paul T. Seamons paul@seamons.com

=head1 SEE ALSO

Please see also
L<Net::Server::Fork>,
L<Net::Server::INET>,
L<Net::Server::PreFork>,
L<Net::Server::MultiType>,
L<Net::Server::Single>

=cut

