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

sub new {
  my $type  = shift;
  my $class = ref($type) || $type || __PACKAGE__;

  my $self = __PACKAGE::SUPER->new( @_ );

  $self->proto('UDP');

  return $self;
}


1;

