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

sub object {
    my ($class, $default_host, $port, $server) = @_;
    my $prop = $server->{'server'};

    $server->configure({
        unix_type      => \$prop->{'unix_type'},
        unix_path      => \$prop->{'unix_path'},
        udp_recv_len   => \$prop->{'udp_recv_len'},
        udp_recv_flags => \$prop->{'udp_recv_flags'},
    });

    my $u_type = $prop->{'unix_type'} || SOCK_STREAM;
    my $u_path = $prop->{'unix_path'} || undef;

    if ($port =~ /^([\w\.\-\*\/]+)\|(\w+)$/) { # allow for things like "/tmp/myfile.sock|SOCK_STREAM"
        ($u_path, $u_type) = ($1, $2);
    } elsif ($port =~ /^([\w\.\-\*\/]+)$/) {   # allow for things like "/tmp/myfile.sock"
        $u_path = $1;
    } else {
        $server->fatal("Unknown unix port type \"$port\" under ".__PACKAGE__);
    }

    if ($u_type eq 'SOCK_STREAM') {
        $u_type = SOCK_STREAM;
    } elsif ($u_type eq 'SOCK_DGRAM') {
        $u_type = SOCK_DGRAM;
    }

    my $sock = $class->SUPER::new();
    if ($u_type == SOCK_DGRAM) {
        $prop->{'udp_recv_len'}   = 4096 if ! defined($prop->{'udp_recv_len'})   || $prop->{'udp_recv_len'}   !~ /^\d+$/;
        $prop->{'udp_recv_flags'} = 0    if ! defined($prop->{'udp_recv_flags'}) || $prop->{'udp_recv_flags'} !~ /^\d+$/;
        $sock->NS_recv_len(   $prop->{'udp_recv_len'} );
        $sock->NS_recv_flags( $prop->{'udp_recv_flags'} );
    } elsif ($u_type != SOCK_STREAM) {
        $server->fatal("Invalid type for UNIX socket ($u_type)... must be SOCK_STREAM or SOCK_DGRAM");
    }
    $sock->NS_unix_type($u_type);
    $sock->NS_unix_path($u_path);

    return $sock;
}

sub log_connect {
    my ($sock, $server) = @_;
    my $type = ($sock->NS_unix_type == SOCK_STREAM) ? 'SOCK_STREAM' : 'SOCK_DGRAM';
    $server->log(2, "Binding to UNIX socket file ".$sock->NS_unix_path." using $type");
}

sub connect {
    my ($sock, $server) = @_;
    my $prop = $server->{'server'};

    my $unix_path = $sock->NS_unix_path;
    my $unix_type = $sock->NS_unix_type;

    my %args = (
        Local  => $unix_path,       # what socket file to bind to
        Type   => $unix_type,       # SOCK_STREAM (default) or SOCK_DGRAM
    );
    $args{'Listen'} = $prop->{'listen'} if $unix_type == SOCK_STREAM;

    if (-e $unix_path && ! unlink($unix_path)) {
        $server->fatal("Can't connect to UNIX socket at file $unix_path [$!]");
    }

    $sock->SUPER::configure(\%args)
        or $server->fatal("Can't connect to UNIX socket at file $unix_path [$!]");
}

sub reconnect { # connect on a sig -HUP
    my ($sock, $fd, $server) = @_;
    $sock->fdopen($fd, 'w') or $server->fatal("Error opening to file descriptor ($fd) [$!]");
}

sub accept {
    my $sock = shift;
    my $client = $sock->SUPER::accept();
    if (defined $client) {
        $client->NS_unix_path($sock->NS_unix_path);
        $client->NS_unix_type($sock->NS_unix_type);
    }
    return $client;
}

### a string containing any information necessary for restarting the server
### via a -HUP signal
### a newline is not allowed
### the hup_string must be a unique identifier based on configuration info
sub hup_string {
    my $sock = shift;
    return join "|", $sock->NS_host, $sock->NS_port, $sock->NS_proto;
}

sub show {
    my $sock = shift;
    my $t = "Ref = \"".ref($sock). "\" (".$sock->hup_string.")\n";
    $t =~ s/\b1\b/SOCK_STREAM/;
    $t =~ s/\b2\b/SOCK_DGRAM/;
    return $t;
}

sub NS_unix_path {
    my $sock = shift;
    ${*$sock}{'NS_unix_path'} = shift if @_;
    return ${*$sock}{'NS_unix_path'};
}

sub NS_unix_type {
    my $sock = shift;
    ${*$sock}{'NS_unix_type'} = shift if @_;
    return ${*$sock}{'NS_unix_type'};
}

sub NS_recv_len {
    my $sock = shift;
    ${*$sock}{'NS_recv_len'} = shift if @_;
    return ${*$sock}{'NS_recv_len'};
}

sub NS_recv_flags {
    my $sock = shift;
    ${*$sock}{'NS_recv_flags'} = shift if @_;
    return ${*$sock}{'NS_recv_flags'};
}

1;

__END__

=head1 NAME

  Net::Server::Proto::UNIX - adp0 - Net::Server UNIX protocol.

=head1 SYNOPSIS

See L<Net::Server::Proto>.

=head1 DESCRIPTION

Protocol module for Net::Server.  This module implements the
SOCK_DGRAM and SOCK_STREAM socket types under UNIX.
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

=item unix_path

Default path to the socket file for this UNIX socket.  Default
is undef.  This can also be passed on the port line (see
L<Net::Server::Proto>).

=item udp_recv_len

Specifies the number of bytes to read from the SOCK_DGRAM connection
handle.  Data will be read into $self->{'server'}->{'udp_data'}.
Default is 4096.  See L<IO::Socket::INET> and L<recv>.

=item udp_recv_flags

See L<recv>.  Default is 0.

=back

=head1 QUICK PARAMETER LIST

  Key               Value                    Default

  ## UNIX socket parameters
  unix_type         (SOCK_STREAM|SOCK_DGRAM) SOCK_STREAM
  unix_path         "filename"               undef
  udp_recv_len      \d+                      4096
  udp_recv_flags    \d+                      0

=head1 LICENCE

Distributed under the same terms as Net::Server

=cut

