# -*- perl -*-
#
#  Net::Server::Proto::UNIX - Net::Server Protocol module
#
#  $Id$
#
#  Copyright (C) 2001-2011
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

package Net::Server::Proto::UNIX;

use strict;
use base qw(IO::Socket::UNIX);
use Socket qw(SOCK_STREAM SOCK_DGRAM);

our $VERSION = $Net::Server::VERSION;

sub NS_proto { 'UNIX' }
sub NS_port  { my $sock = shift; ${*$sock}{'NS_port'}   = shift if @_; return ${*$sock}{'NS_port'}   }
sub NS_host  { '*' }
sub NS_ipv   { '*' }
sub NS_listen { my $sock = shift; ${*$sock}{'NS_listen'} = shift if @_; return ${*$sock}{'NS_listen'} }
sub NS_unix_type { 'SOCK_STREAM' }

sub object {
    my ($class, $info, $server) = @_;
    my $prop = $server->{'server'};

    if ($class eq __PACKAGE__) {
        my $type;
        $server->configure({unix_type => \$type});
        my $u_type = uc(defined($info->{'unix_type'}) ? $info->{'unix_type'} : defined($type) ? $type : 'SOCK_STREAM');
        if ($u_type eq 'SOCK_DGRAM' || $u_type eq ''.SOCK_DGRAM()) { # allow for legacy invocations passing unix_type to UNIX - now just use proto UNIXDGRAM
            require Net::Server::Proto::UNIXDGRAM;
            return Net::Server::Proto::UNIXDGRAM->object($info, $server);
        } elsif ($u_type ne 'SOCK_STREAM' && $u_type ne ''.SOCK_STREAM()) {
            $server->fatal("Invalid type for UNIX socket ($u_type)... must be SOCK_STREAM or SOCK_DGRAM");
        }
    }

    my $listen = defined($info->{'listen'}) ? $info->{'listen'} : defined($prop->{'listen'}) ? $prop->{'listen'} : Socket::SOMAXCONN();
    my $sock = $class->SUPER::new();
    $sock->NS_port($info->{'port'});
    $sock->NS_listen($listen) if defined $listen;
    return $sock;
}

sub connect {
    my ($sock, $server) = @_;
    my $path = $sock->NS_port;
    $server->fatal("Can't connect to UNIX socket at file $path [$!]") if -e $path && ! unlink $path;

    $sock->SUPER::configure({
        Local  => $path,
        Type   => SOCK_STREAM,
        Listen => $sock->NS_listen,
    }) or $server->fatal("Can't connect to UNIX socket at file $path [$!]");
}

sub log_connect {
    my ($sock, $server) = @_;
    $server->log(2, "Binding to ".$sock->NS_proto." socket file \"".$sock->NS_port."\"");
}

sub reconnect { # connect on a sig -HUP
    my ($sock, $fd, $server) = @_;
    $sock->fdopen($fd, 'w') or $server->fatal("Error opening to file descriptor ($fd) [$!]");
}

### a string containing any information necessary for restarting the server
### via a -HUP signal
### a newline is not allowed
### the hup_string must be a unique identifier based on configuration info
sub hup_string {
    my $sock = shift;
    return join "|", $sock->NS_host, $sock->NS_port, $sock->NS_proto, $sock->NS_ipv;
}

sub show {
    my $sock = shift;
    return "Ref = \"".ref($sock). "\" (".$sock->hup_string.")\n";
}

1;

__END__

=head1 NAME

  Net::Server::Proto::UNIX - adp0 - Net::Server UNIX protocol.

=head1 SYNOPSIS

See L<Net::Server::Proto>.

=head1 DESCRIPTION

Protocol module for Net::Server.  This module implements the
UNIX SOCK_STREAM socket type.
See L<Net::Server::Proto>.

Any sockets created during startup will be chown'ed to the
user and group specified in the starup arguments.

=head1 PARAMETERS

The following paramaters may be specified in addition to
normal command line parameters for a Net::Server.  See
L<Net::Server> for more information on reading arguments.

=over 4

=item unix_type

Can be either SOCK_STREAM or SOCK_DGRAM (default is SOCK_STREAM).
This can also be passed on the port line (see L<Net::Server::Proto>).

However, this method is deprecated.  If you want SOCK_STREAM - just use
proto UNIX without any other arguments.  If you'd like SOCK_DGRAM, use the
new proto UNIXDGRAM.

=back

=head1 QUICK PARAMETER LIST

  Key               Value                    Default

  ## UNIX socket parameters
  unix_type         (SOCK_STREAM|SOCK_DGRAM) SOCK_STREAM
  port              "filename"               undef

=head1 LICENCE

Distributed under the same terms as Net::Server

=cut

