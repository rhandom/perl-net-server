# -*- perl -*-
#
#  Net::Server::Buffer - Net::Server line buffer module
#
#  $Id$
#
#  Copyright (C) 2001-2005
#
#    Paul Seamons
#    paul@seamons.com
#    http://seamons.com/
#
#  This package may be distributed under the terms of either the
#  GNU General Public License
#    or the
#  Perl Artistic License
#
#  All rights reserved.
#
################################################################

package Net::Server::Buffer;

use vars qw(@ISA $VERSION @EXPORT_OK $AUTOLOAD);
use strict;
use Exporter ();

use constant LF => "\012";

$VERSION = $Net::Server::VERSION; # done until separated

@ISA = qw(Exporter);
@EXPORT_OK = qw(set_getline_buffer dgetline);


{
  package Net::Server::Buffer::IO::File;
  use vars qw(@ISA);
  use IO::File;
  @ISA = qw(IO::File);
}

sub set_getline_buffer {
  my $args = {@_};
  my $ref  = $args->{handle} ? ref( $args->{handle} ) : undef;

  die "Usage: set_readline_buffer(handle => \$fh)"
    unless $ref;
  
  $args->{read_length} = 8192
    unless $args->{read_length} && $args->{read_length} !~ /\D/;
  
  $args->{max_line_length} = 102400
    unless $args->{max_line_length} && $args->{max_line_length} !~ /\D/;

  my $package  = __PACKAGE__;

  ### install a new package
  ### if the ref is IO::Socket, install Net::Server::Buffer::IO::Socket
  ### install some properties into a new pacakge
  no     strict 'refs';
  * { "${package}::${ref}::ISA" }      = \@ { [$package] }; # double, but verbose
  * { "${package}::${ref}::getline" }  = \& { "${package}::getline" };
  * { "${package}::${ref}::AUTOLOAD" } = \& { "${package}::AUTOLOAD" };
  import strict 'refs';

  ### turn the handle into that package
  bless $args->{handle}, "${package}::${ref}";

  ### store some properties in the handle
  $ { *{ $args->{handle} } }{read_length}     = $args->{read_length};
  $ { *{ $args->{handle} } }{max_line_length} = $args->{max_line_length};
  $ { *{ $args->{handle} } }{buffer}          = '';

  use Symbol qw(gensym);
  $args->{handle} = bless gensym(), "${package}";
}

sub getline {
  @_ == 1 or die 'usage: $io->getline()';
  my $this = shift;
  my $read_len = $ { *$this }{read_length};
  my $buffer   = $ { *$this }{buffer};
  my $max_len  = $ { *$this }{max_line_length};

  my $index = index($buffer,LF);

  while( $index == -1 ){
    $this->sysread($buffer, $read_len, length($buffer) );

    if( length($buffer) > $max_len ){
      $! = "Max line length exceeded";
      return undef;
    }

    $index = index($buffer,LF)
  }

  return substr($buffer, 0, $index, '');
} 

sub AUTOLOAD {
  my $self = shift;
  require "Carp.pm";
  &Carp::confess( $AUTOLOAD );
}

1;
