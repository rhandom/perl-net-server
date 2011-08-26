# -*- perl -*-
#
#  Net::Server::Proto::TCP - Net::Server Protocol module
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

package Net::Server::Proto::TCP;

use strict;
use base qw(IO::Socket::INET);

our $VERSION = $Net::Server::VERSION;
our $have_inet6;
our $NS_bam = 1;
sub NS_proto { 'TCP' }

sub object {
    my ($class, $default_host, $port, $server) = @_;

    my $host;
    if ($port =~ /^([\w\.\-\*\/]+):(\w+)$/) { # allow for things like "domain.com:80"
        ($host, $port) = ($1, $2);
    } elsif ($port =~ /^(\w+)$/) { # allow for things like "80"
        ($host, $port) = ($default_host, $1);
    } else {
        $server->fatal("Unknown port type \"$port\" under ".__PACKAGE__);
    }

    my $sock = $class->SUPER::new();
    $sock->NS_host($host);
    $sock->NS_port($port);
    return $sock;
}

sub log_connect {
    my ($sock, $server) = @_;
    $server->log(2, "Binding to ".$sock->NS_proto." port ".$sock->NS_port." on host ".$sock->NS_host." with PF ".($sock->NS_family || 0));
}

sub connect {
    my ($sock, $server) = @_;
    my $prop = $server->{'server'};
    my $host = $sock->NS_host;
    my $port = $sock->NS_port;
    my $pfamily = $sock->NS_family;

    my %args = (
        LocalPort => $port,
        Proto     => 'tcp',
        Listen    => $prop->{'listen'},
        ReuseAddr => 1, Reuse => 1,  # allow us to rebind the port on a restart
    );
    $args{'LocalAddr'} = $host if $host !~ /\*/; # what local address (* is all)
    $args{'Domain'}    = $pfamily if $have_inet6 && $pfamily;

    $sock->SUPER::configure(\%args) || $server->fatal("Can't connect to TCP port $port on $host [$!]");

    if ($port == 0 && ($port = $sock->sockport)) {
        $sock->NS_port($port);
        $server->log(2, "Bound to auto-assigned port $port");
    }
}

sub reconnect { # after a sig HUP
    my ($sock, $fd, $server) = @_;
    $server->log(3,"Reassociating file descriptor $fd with ".$sock->NS_proto." on [".$sock->NS_host."]:".$sock->NS_port.", PF ".$sock->NS_family);
    $sock->fdopen($fd, 'w') or $server->fatal("Error opening to file descriptor ($fd) [$!]");
}

sub poll_cb { # implemented for psgi compatibility - TODO - should poll appropriately for Multipex
    my ($self, $cb) = @_;
    return $cb->($self);
}

###----------------------------------------------------------------###

sub read_until { # only sips the data - but it allows for compatibility with SSLEAY
    my ($client, $bytes, $end_qr) = @_;
    die "One of bytes or end_qr should be defined for TCP read_until\n" if !defined($bytes) && !defined($end_qr);
    my $content = '';
    my $ok = 0;
    while (1) {
        $client->read($content, 1, length($content));
        if (defined($bytes) && length($content) >= $bytes) {
            $ok = 2;
            last;
        } elsif (defined($end_qr) && $content =~ $end_qr) {
            $ok = 1;
            last;
        }
    }
    return wantarray ? ($ok, $content) : $content;
}

###----------------------------------------------------------------###

### a string containing any information necessary for restarting the server
### via a -HUP signal
### a newline is not allowed
### the hup_string must be a unique identifier based on configuration info
sub hup_string {
    my $sock = shift;
    return join "|", $sock->NS_host, $sock->NS_port, $sock->NS_proto, $sock->NS_family;
}

sub show {
    my $sock = shift;
    return "Ref = \"".ref($sock). "\" (".$sock->hup_string.")\n";
}

sub NS_port {
    my $sock = shift;
    ${*$sock}{'NS_port'} = shift if @_;
    return ${*$sock}{'NS_port'};
}

sub NS_host {
    my $sock = shift;
    ${*$sock}{'NS_host'} = shift if @_;
    return ${*$sock}{'NS_host'};
}

sub NS_family { 0 }

1;

__END__

=head1 NAME

  Net::Server::Proto::TCP - Net::Server TCP protocol.

=head1 SYNOPSIS

See L<Net::Server::Proto>.

=head1 DESCRIPTION

Protocol module for Net::Server.  This module implements the
SOCK_STREAM socket type under INET (also known as TCP).
See L<Net::Server::Proto>.

=head1 PARAMETERS

There are no additional parameters that can be specified.
See L<Net::Server> for more information on reading arguments.

=head1 INTERNAL METHODS

=over 4

=item C<object>

Returns an object with parameters suitable for eventual creation of
a IO::Socket::INET object listining on UDP.

=item C<log_connect>

Called before binding the socket to provide useful information to the logs.

=item C<connect>

Called when actually binding the port.  Handles default parameters
before calling parent method.

=item C<reconnect>

Called instead of connect method during a server hup.

=item C<accept>

Override of the parent class to make sure necessary parameters are passed down to client sockets.

=item C<poll_cb>

Allow for psgi compatible interface during HTTP server.

=item C<read_until>

Takes a regular expression, reads from the socket until the regular expression is matched.

=item C<hup_string>

Returns a unique identifier that can be passed to the re-exec'ed process during HUP.

=item C<show>

Basic dumper of properties stored in the glob.

=item C<AUTOLOAD>

Handle accessor methods.

=head1 LICENCE

Distributed under the same terms as Net::Server

=cut

