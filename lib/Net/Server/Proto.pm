# -*- perl -*-
#
#  Net::Server::PreFork - Net::Server Protocol
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

package Net::Server::Proto;

use strict;
use vars qw($VERSION $AUTOLOAD);

$VERSION = $Net::Server::VERSION; # done until separated


sub new {
  my $type  = shift;
  my $class = ref($type) || $type || __PACKAGE__;

  my ($default_host,$port,$default_proto,$server) = @_;
  my $proto_class;

  ### first find the proto
  if( $port =~ s|/([\w:]+)$|| ){
    $proto_class = $1;
  }else{
    $proto_class = $default_proto;
  }


  ### using the proto, load up a module for that proto
  ## for example, "tcp" will load up Net::Server::Proto::TCP.
  ## "unix" will load Net::Server::Proto::UNIX.
  ## "Net::Server::Proto::UDP" will load itself.
  ## "Custom::Proto::TCP" will load itself.
  if( $proto_class !~ /::/ ){
    
    if( $proto_class !~ /^\w+$/ ){
      $server->fatal("Invalid Protocol class \"$proto_class\"");
    }

    $proto_class = "Net::Server::Proto::" .uc($proto_class);

  }


  ### get the module filename
  my $proto_class_file = $proto_class .".pm";
  $proto_class_file =~ s|::|/|g;

  
  ### try to load the module (this is before any forking so this is still shared)
  if( ! eval{ require $proto_class_file } ){
    $server->fatal("Unable to load module: $@");
  }


  ### return an object of that procol class
  return $proto_class->new($default_host,$port,$server);

}


### self installer
sub AUTOLOAD {
  my $self = shift;

  my ($prop) = $AUTOLOAD =~ /::([^:]+)$/ ? $1 : '';
  if( ! $prop ){
    die "No property called.";
  }

  if( $prop =~ /^(proto|port|host|sock|fd)$/ ){
    no strict 'refs';
    * { __PACKAGE__ ."::". $prop } = sub {
      my $self = shift;
      if( @_ ){
        $self->{$prop} = shift;
        delete $self->{$prop} unless defined $self->{$prop};
      }else{
        return $self->{$prop};
      }
    };
    use strict 'refs';

    $self->$prop(@_);

  }else{
    die "What method is that? [$prop]";
  }
}


1;

