# -*- perl -*-
#
#  Net::Server::Proto::UDP - Net::Server Protocol module
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

package Net::Server::Proto::UDP;

use strict;
use vars qw($VERSION $AUTOLOAD @ISA);
use Net::Server::Proto::TCP ();

$VERSION = $Net::Server::VERSION; # done until separated
@ISA = qw(Net::Server::Proto::TCP);

sub object {
  my $type  = shift;
  my $class = ref($type) || $type || __PACKAGE__;

  my $self = $class->SUPER::object( @_ );

  $self->NS_proto('UDP');

  return $self;
}


### connect the first time
### doesn't support the listen or the reuse option
sub connect {
  my $sock   = shift;
  my $server = shift;
  my $prop   = $server->{server};

  my $host  = $sock->NS_host;
  my $port  = $sock->NS_port;

  $server->log(2,"Binding to UDP port $port on host $host\n");
      
  my %args = ();
  $args{LocalPort} = $port;                  # what port to bind on
  $args{Proto}     = 'udp';                  # what procol to use
  $args{LocalAddr} = $host if $host !~ /\*/; # what local address (* is all)

  ### connect to the sock
  $sock->SUPER::configure(\%args)
    or $server->fatal("Can't connect to UDP port $port on $host [$!]");

  $server->fatal("Back sock [$!]!".caller())
    unless $sock;

}


1;

