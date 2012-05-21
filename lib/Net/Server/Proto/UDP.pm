# -*- perl -*-
#
#  Net::Server::Proto::UDP - Net::Server Protocol module
#
#  $Id$
#
#  Copyright (C) 2001-2012
#
#    Paul Seamons
#    paul@seamons.com
#    http://seamons.com/
#
#  Modified 2005 by Timothy Watt
#    Added ability to deal with broadcast packets.
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
use base qw(Net::Server::Proto::TCP);

sub NS_proto { 'UDP' }
sub NS_recv_len   { my $sock = shift; ${*$sock}{'NS_recv_len'}   = shift if @_; return ${*$sock}{'NS_recv_len'}   }
sub NS_recv_flags { my $sock = shift; ${*$sock}{'NS_recv_flags'} = shift if @_; return ${*$sock}{'NS_recv_flags'} }
sub NS_broadcast  { my $sock = shift; ${*$sock}{'NS_broadcast'}  = shift if @_; return ${*$sock}{'NS_broadcast'}  }

sub object {
    my ($class, $info, $server) = @_;

    my ($len, $flags, $broadcast);
    $server->configure({
        udp_recv_len   => \$len,
        udp_recv_flags => \$flags,
        udp_broadcast  => \$broadcast,
    });
    $len   = defined($info->{'udp_recv_len'})   ? $info->{'udp_recv_len'}   : (defined($len)   && $len   =~ /^(\d+)$/) ? $1 : 4096;
    $flags = defined($info->{'udp_recv_flags'}) ? $info->{'udp_recv_flags'} : (defined($flags) && $flags =~ /^(\d+)$/) ? $1 : 0;

    my @sock = $class->SUPER::new(); # it is possible that multiple connections will be returned if INET6 is in effect
    foreach my $sock (@sock) {
        $sock->NS_host($info->{'host'});
        $sock->NS_port($info->{'port'});
        $sock->NS_ipv6($info->{'ipv6'} || 0);
        $sock->NS_recv_len($len);
        $sock->NS_recv_flags($flags);
        $sock->NS_broadcast($broadcast);
    }
    return wantarray ? @sock : $sock[0];
}

sub connect {
    my ($sock, $server) = @_;
    my $host = $sock->NS_host;
    my $port = $sock->NS_port;
    my $ipv6 = $sock->NS_ipv6;
    my $require_ipv6 = Net::Server::Proto->requires_ipv6($server);

    $sock->SUPER::configure({
        LocalPort => $port,
        Proto     => 'udp',
        ReuseAddr => 1,
        Reuse => 1, # may not be needed on UDP
        ($host !~ /\*/ ? (LocalAddr => $host) : ()), # * is all
        ($require_ipv6 ? (Domain => $ipv6 ? Socket6::AF_INET6() : Socket::AF_INET()) : ()),
        ($sock->NS_broadcast ? (Broadcast => 1) : ()),
    }) or $server->fatal("Cannot bind to UDP port $port on $host [$!]");

    if ($port == 0 && ($port = $sock->sockport)) {
        $sock->NS_port($port);
        $server->log(2, "Bound to auto-assigned port $port");
    }
}

1;

__END__

=head1 NAME

  Net::Server::Proto::UDP - Net::Server UDP protocol.

=head1 SYNOPSIS

See L<Net::Server::Proto>.

=head1 DESCRIPTION

Protocol module for Net::Server.  This module implements the
SOCK_DGRAM socket type under INET (also known as UDP).
See L<Net::Server::Proto>.

=head1 PARAMETERS

The following paramaters may be specified in addition to
normal command line parameters for a Net::Server.  See
L<Net::Server> for more information on reading arguments.

=over 4

=item udp_recv_len

Specifies the number of bytes to read from the UDP connection
handle.  Data will be read into $self->{'server'}->{'udp_data'}.
Default is 4096.  See L<IO::Socket::INET> and L<recv>.

=item udp_recv_flags

See L<recv>.  Default is 0.

=item udp_broadcast

Default is undef.

=back

=head1 QUICK PARAMETER LIST

  Key               Value                    Default

  ## UDP protocol parameters
  udp_recv_len      \d+                      4096
  udp_recv_flags    \d+                      0
  udp_broadcast     bool                     undef

=head1 INTERNAL METHODS

=over 4

=item C<object>

Returns an object with parameters suitable for eventual creation of
a IO::Socket::INET object listining on UDP.

=item C<connect>

Called when actually binding the port.  Handles default parameters
before calling parent method.

=back

=head1 LICENCE

Distributed under the same terms as Net::Server

=cut

