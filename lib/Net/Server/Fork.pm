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
use IO::Select ();

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

  ### how often to see if children are alive
  $prop->{check_for_dead} = 30
    unless defined $prop->{check_for_dead};

  ### what are the max number of processes
  $prop->{max_servers} = 25
    unless defined $prop->{max_servers};

  ### I need to know who is the parent
  $prop->{ppid} = $$;

}

### loop, fork, and process connections
sub loop {
  my $self = shift;
  my $prop = $self->{server};

  ### get ready for children
  $prop->{children} = {};

  my $last_checked_for_dead = time;

  ### this is the main loop
  while( 1 ){
    
    $self->accept;
    
    my $pid = fork;

    ### trouble
    if( not defined $pid ){
      $self->log(1,"Bad fork [$!]");
      sleep(5);
      
    ### parent
    }elsif( $pid ){
      close($prop->{client});
      $prop->{children}->{$pid} = time;
      
    ### child
    }else{
      $self->run_client_connection;
      exit;
      
    }

    ### periodically see which children are alive
    my $time = time;
    if( $time - $last_checked_for_dead > $prop->{check_for_dead} ){
      $last_checked_for_dead = $time;
      foreach (keys %{ $prop->{children} }){
        ### see if the child can be killed
        kill(0,$_) or delete $prop->{children}->{$_};
      }
    }

  }
}

### override a little to restore sigs
sub run_client_connection {
  my $self = shift;

  ### close the main sock, we still have
  ### the client handle, this will allow us
  ### to HUP the parent at any time
  $_ = undef foreach @{ $self->{server}->{sock} };

  ### restore sigs (turn off warnings during)
  $SIG{INT} = $SIG{TERM} = $SIG{QUIT} = 'DEFAULT';

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

  Net::Server::Fork->run();

=head1 DESCRIPTION

Please read the pod on Net::Server first.  This module
is a personality, or extension, or sub class, of the
Net::Server module.

This personality binds to one or more ports and then waits
for a client connection.  When a connection is received,
the server forks a child.  The child handles the request
and then closes.

=head1 ARGUMENTS

There are no additional arguments beyond the Net::Server
base class.

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

