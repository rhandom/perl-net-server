# -*- perl -*-
#
#  Net::Server::Proto::UNIX - Net::Server Protocol module
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

package Net::Server::Proto::UNIX;

use strict;
use vars qw($VERSION $AUTOLOAD @ISA);
use IO::Socket::UNIX ();
use Socket qw(SOCK_STREAM SOCK_DGRAM);

$VERSION = $Net::Server::VERSION; # done until separated
@ISA = qw(IO::Socket::UNIX);

sub object {
  my $type  = shift;
  my $class = ref($type) || $type || __PACKAGE__;

  my ($default_host,$port,$server) = @_;

  my $u_type = $server->{server}->{unix_type} || SOCK_STREAM;
  my $u_path = $server->{server}->{unix_path} || undef;

  ### allow for things like "/tmp/myfile.sock|SOCK_STREAM"
  if( $port =~ m/^([\w\.\-\*\/]+)\|(\d+)$/ ){
    ($u_path,$u_type) = ($1,$2);

  ### allow for things like "/tmp/myfile.sock"
  }elsif( $port =~ /^([\w\.\-\*\/]+)$/ ){
    $u_path = $1;

  ### don't know that style of port
  }else{
    $server->fatal("Undeterminate port \"$port\" under ".__PACKAGE__);
  }

  if( $u_type != SOCK_STREAM && $u_type != SOCK_DGRAM ){
    $server->fatal("Invalid type for UNIX socket ($u_type)... must be SOCK_STREAM or SOCK_DGRAM");
  }

  my $sock = $class->SUPER::new();

  $sock->NS_unix_type( $u_type );
  $sock->NS_unix_path( $u_path );
  $sock->NS_proto('UNIX');
  
  return $sock;
}

sub log_connect {
  my $sock = shift;
  my $server    = shift;
  my $unix_path = $sock->NS_unix_path;
  $server->log(2,"Binding to UNIX socket at file $unix_path\n");
}

### connect the first time
### doesn't support the listen or the reuse option
sub connect {
  my $sock   = shift;
  my $server = shift;
  my $prop   = $server->{server};

  my $unix_path = $sock->NS_unix_path;
  my $unix_type = $sock->NS_unix_type;

  my %args = ();
  $args{Local}  = $unix_path;       # what socket file to bind to
  $args{Type}   = $unix_type;       # SOCK_STREAM (default) or SOCK_DGRAM
  $args{Listen} = $prop->{listen};  # how many connections for kernel to queue

  ### remove the old socket if it is still there
  if( -e $unix_path && ! unlink($unix_path) ){
    $server->fatal("Can't connect to UNIX socket at file $unix_path [$!]");
  }

  ### connect to the sock
  $sock->SUPER::configure(\%args)
    or $server->fatal("Can't connect to UNIX socket at file $unix_path [$!]");

  $server->fatal("Back sock [$!]!".caller())
    unless $sock;

}

### connect on a sig -HUP
sub reconnect {
  my $sock = shift;
  my $fd   = shift;
  my $server = shift;

  $sock->fdopen( $fd, 'w' )
    or $server->fatal("Error opening to file descriptor ($fd) [$!]");

}

### allow for endowing the child
sub accept {
  my $sock = shift;
  my $client = $sock->SUPER::accept();

  ### pass items on
  if( defined($client) ){
    $client->NS_proto(     $sock->NS_proto );
    $client->NS_unix_path( $sock->NS_unix_path );
  }

  return $client;
}

### a string containing any information necessary for restarting the server
### via a -HUP signal
### a newline is not allowed
### the hup_string must be a unique identifier based on configuration info
sub hup_string {
  my $sock = shift;
  return join("|",
              $sock->NS_unix_path,
              $sock->NS_unix_type,
              $sock->NS_proto,
              );
}

### self installer
sub AUTOLOAD {
  my $sock = shift;

  my ($prop) = $AUTOLOAD =~ /::([^:]+)$/ ? $1 : '';
  if( ! $prop ){
    die "No property called.";
  }

  if( $prop =~ /^(NS_proto|NS_unix_path|NS_unix_type)$/ ){
    no strict 'refs';
    * { __PACKAGE__ ."::". $prop } = sub {
      my $sock = shift;
      if( @_ ){
        ${*$sock}{$prop} = shift;
        delete ${*$sock}{$prop} unless defined ${*$sock}{$prop};
      }else{
        return ${*$sock}{$prop};
      }
    };
    use strict 'refs';

    $sock->$prop(@_);

  }else{
    die "What method is that? [$prop]";
  }
}



1;

