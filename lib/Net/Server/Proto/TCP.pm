# -*- perl -*-
#
#  Net::Server::Proto::TCP - Net::Server Protocol module
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

package Net::Server::Proto::TCP;

use strict;
use vars qw($VERSION $AUTOLOAD @ISA);

$VERSION = $Net::Server::VERSION; # done until separated
@ISA = qw(Net::Server::Proto);

sub new {
  my $type  = shift;
  my $class = ref($type) || $type || __PACKAGE__;

  my ($default_host,$port,$server) = @_;
  my $host;

  ### allow for things like "domain.com:80"
  if( $port =~ m|^([\w\.\-\*\/]+):(\w+)$| ){
    ($host,$port) = ($1,$2);

  ### allow for things like "80"
  }elsif( /^(\w+)$/ ){
    ($host,$port) = ($default_host,$1);

  ### don't know that style of port
  }else{
    $server->fatal("Undeterminate port \"$port\" under TCP");
  }

  my $self = bless {}, $class;

  ### store some properties
  $self->host($host);
  $self->port($port);
  $self->proto('TCP');

  return $self;
}


1;

