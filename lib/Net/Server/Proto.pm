# -*- perl -*-
#
#  Net::Server::Proto - Net::Server Protocol compatibility layer
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

package Net::Server::Proto;

use strict;

sub parse_info {
    my ($class, $port, $host, $proto, $server) = @_;
    if ($port && ref($port) ne 'HASH' && $port =~ m{ (.+) [,|/] (\w+ (?:::\w+)*) $ }x) {
        ($port, $proto) = ($1, $2);
    }

    my $info;
    if (ref($port) eq 'HASH') {
        die "Missing port in hashref passed in port argument.\n" if ! $port->{'port'};
        $info = $port;
    } else {
        $info = {};
        ($port, $info->{'unix_type'}) = ($1, $2) if $port =~ m{ (.+) [,|/] (sock_(?:stream|dgram)) $ }x; # legacy /some/path|sock_dgram
        if (     $port =~ m{^ \[ ([\w/.\-:]+ | \*) \] [,|:](\w+) $ }x) { # allow for things like "[::1]:80" or "[host.example.com]:80"
            @$info{qw(host port)} = ($1, $2);
        } elsif ($port =~ m{^    ([\w/.\-:]+ | \*)    [,|:](\w+) $ }x) { # allow for things like "127.0.0.1:80" or "host.example.com:80"
            @$info{qw(host port)} = ($1, $2);
        } else {
            $info->{'port'} = $port;
        }
    }

    $info->{'host'} ||= (!defined($host) || $host eq '') ? '*'
        : ($host =~ m{^ \[ ([\w/.\-:]+ | :?\*) \] $ }x) ? $1
        : ($host =~ m{^    ([\w/.\-:]+ | :?\*)    $ }x) ? $1
        : $server->fatal("Could not determine host from \"$host\"");

    $info->{'proto'} ||= !$proto ? 'tcp'
        : ($proto =~ /^(\w+ (?:::\w+)*)$/x) ? $1
        : $server->fatal("Could not determine proto from \"$proto\"");

    $info->{'ipv6'} = 1 if $info->{'host'} =~ /:/;

    return $info;
}

sub object {
    my ($class, $info, $server) = @_;
    my $proto_class = $info->{'proto'};
    if ($proto_class !~ /::/) {
        $server->fatal("Invalid proto class \"$proto_class\"") if $proto_class !~ /^\w+$/;
        $proto_class = "Net::Server::Proto::" .uc($proto_class);
    }
    (my $file = "${proto_class}.pm") =~ s|::|/|g;
    $server->fatal("Unable to load module for proto \"$proto_class\": $@") if ! eval { require $file };
    return $proto_class->object($info, $server);
}

1;

__END__

=head1 NAME

    Net::Server::Proto - Net::Server Protocol compatibility layer

=head1 SYNOPSIS

    # Net::Server::Proto and its accompanying modules are not
    # intended to be used outside the scope of Net::Server.

    # That being said, here is how you use them.  This is
    # only intended for anybody wishing to extend the
    # protocols to include some other set (ie maybe a
    # database connection protocol)

    use Net::Server::Proto;

    my $info = Net::Server::Proto->parse_info(
        $port,            # port to connect to
        $default_host,    # host to use if none found in port
        $default_proto,   # proto to use if none found in port
        $server_obj,      # Net::Server object
    );

    my $sock = Net::Server::Proto->object({
        port => $port,
        host => $host,
        proto => $proto,
    }, $server);

    # Net::Server::Proto will attempt to interface with
    # sub modules named similar to Net::Server::Proto::TCP
    # Individual sub modules will be loaded by
    # Net::Server::Proto as they are needed.

    use Net::Server::Proto::TCP; # or UDP or UNIX etc

    # Return an object which is a sub class of IO::Socket
    # At this point the object is not connected.
    # The method can gather any other information that it
    # needs from the server object.
    my $sock = Net::Server::Proto::TCP->object({
        port => $port,
        host => $host,
        proto => $proto,
    }, $server);


    # Log that a connection is about to occur.
    # Use the facilities of the passed Net::Server object.
    $sock->log_connect( $server );

    # Actually bind to port or socket file.  This
    # is typically done by calling the configure method.
    $sock->connect();

    # Allow for rebinding to an already open fileno.
    # Typically will just do an fdopen.
    $sock->reconnect();

    ### Return a unique identifying string for this sock that
    # can be used when reconnecting.
    my $str = $sock->hup_string();

    # Return the proto that is being used by this module.
    my $proto = $sock->NS_proto();


=head1 DESCRIPTION

Net::Server::Proto is an intermediate module which returns IO::Socket
style objects blessed into its own set of classes (ie
Net::Server::Proto::TCP, Net::Server::Proto::UNIX).

Only three or four protocols come bundled with Net::Server.  TCP, UDP,
UNIX, UNIXDGRAM, and SSLEAY.  TCP is an implementation of SOCK_STREAM
across an INET socket.  UDP is an implementation of SOCK_DGRAM across
an INET socket.  UNIX uses a unix style socket file with the
SOCK_STREAM protocol.  UNIXGRAM uses a unix style socket file with the
SOCK_DGRAM protocol.  SSLEAY is actually just a layer on top of TCP
but uses Net::SSLeay to read and write from the stream.

The protocol that is passed to Net::Server can be the name of another
module which contains the protocol bindings.  If a protocol of
MyServer::MyTCP was passed, the socket would be blessed into that
class.  If Net::Server::Proto::TCP was passed, it would get that
class.  If a bareword, such as tcp, udp, unix, unixdgram or ssleay, is
passed, the word is uppercased, and post pended to
"Net::Server::Proto::" (ie tcp = Net::Server::Proto::TCP).

=head1 METHODS

Protocol names used by the Net::Server::Proto should be sub classes of
IO::Socket.  These classes should also contain, as a minimum, the
following methods:

=over 4

=item object

Return an object which is a sub class of IO::Socket At this point the
object is not connected.  The method can gather any other information
that it needs from the server object.  Arguments are default_host,
port, and a Net::Server style server object.

=item log_connect

Log that a connection is about to occur.  Use the facilities of the
passed Net::Server object.  This should be an informative string
explaining which properties are being used.

=item connect

Actually bind to port or socket file.  This is typically done
internally by calling the configure method of the IO::Socket super
class.

=item reconnect

Allow for rebinding to an already open fileno.  Typically will just do
an fdopen using the IO::Socket super class.

=item hup_string

Return a unique identifying string for this sock that can be used when
reconnecting.  This is done to allow information including the file
descriptor of the open sockets to be passed via %ENV during an exec.
This string should always be the same based upon the configuration
parameters.

=item NS_port

Net::Server protocol.  Return the port that is being used by this
module.  If the underlying type is UNIX then port will actually be
the path to the unix socket file.

=item NS_host

Net::Server protocol.  Return the protocol that is being used by this
module.  This does not have to be a registered or known protocol.

=item NS_proto

Net::Server protocol.  Return the protocol that is being used by this
module.  This does not have to be a registered or known protocol.

=item show

Similar to log_connect, but simply shows a listing of which
properties were found.  Can be used at any time.

=back

=head1 PORT

The port is the most important argument passed to the sub
module classes and to Net::Server::Proto itself.  For tcp,
udp, and ssleay style ports, the form is generally host:port/protocol,
[host]:port/protocol, host|port|protocol, host/port, or port.
If I<host> is a numerical IPv6 address it must be enclosed in square
brackets to avoid ambiguity in parsing a port number, e.g.: "[::1]:80".
For unix sockets the form is generally socket_file|unix or socket_file.

A socket protocol family PF_INET or PF_INET6 is derived from a specified
address family of the binding address. A PF_INET socket can only accept
IPv4 connections. A PF_INET6 socket accepts IPv6 connections, but may also
accept IPv4 connections, depending on OS and its settings. For example,
on FreeBSD systems setting a sysctl net.inet6.ip6.v6only to 0 will allow
IPv4 connections to a PF_INET6 socket.

The Net::Server::Proto::object method returns a list of objects corresponding
to created sockets. For Unix and INET sockets the list typically contains
just one element, but may return multiple objects when multiple protocol
families are allowed or when a host name resolves to multiple local
binding addresses.

You can see what Net::Server::Proto parsed out by looking at
the logs to see what log_connect said.  You could also include
a post_bind_hook similar to the following to debug what happened:

    sub post_bind_hook {
        my $self = shift;
        foreach my $sock ( @{ $self->{server}->{sock} } ){
            $self->log(2,$sock->show);
        }
    }

Rather than try to explain further, please look at the following
examples:

    # example 1 #----------------------------------

    $port      = "20203";
    $def_host  = "default-domain.com";
    $def_proto = undef;
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'default-domain.com',
    #     port  => 20203,
    #     proto => 'tcp', # will use Net::Server::Proto::TCP
    # };

    # example 2 #----------------------------------

    $port      = "someother.com:20203";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'someother.com',
    #     port  => 20203,
    #     proto => 'tcp', # will use Net::Server::Proto::TCP
    # };

    # example 3 #----------------------------------

    $port      = "someother.com:20203/udp";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'someother.com',
    #     port  => 20203,
    #     proto => 'udp', # will use Net::Server::Proto::UDP
    # };

    # example 4 #----------------------------------

    $port      = "someother.com:20203/Net::Server::Proto::UDP";
    $def_host  = "default-domain.com";
    $def_proto = "TCP";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'someother.com',
    #     port  => 20203,
    #     proto => 'Net::Server::Proto::UDP',
    # };

    # example 5 #----------------------------------

    $port      = "someother.com:20203/MyObject::TCP";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'someother.com',
    #     port  => 20203,
    #     proto => 'MyObject::TCP',
    # };

    # example 6 #----------------------------------

    $port      = "/tmp/mysock.file|unix";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => '*', # irrelevant for UNIX socket
    #     port  => '/tmp/mysock.file', # not really a port
    #     proto => 'unix', # will use Net::Server::Proto::UNIX
    # };

    # example 7 #----------------------------------

    $port      = "/tmp/mysock.file|unixdgram";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => '*', # irrelevant for UNIX socket
    #     port  => '/tmp/mysock.file', # not really a port
    #     proto => 'unixdgram', # will use Net::Server::Proto::UNIXDGRAM
    # };

    # example 8 #----------------------------------

    $port      = "/tmp/mysock.file|SOCK_STREAM|unix"; # legacy
    $def_host  = "";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => '*', # irrelevant for UNIX socket
    #     port  => '/tmp/mysock.file', # not really a port
    #     proto => 'unix', # will use Net::Server::Proto::UNIX
    #     unix_type => 'SOCK_STREAM',
    # };

    # example 9 #----------------------------------

    $port      = "/tmp/mysock.file|SOCK_DGRAM|unix"; # legacy
    $def_host  = "";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => '*', # irrelevant for UNIX socket
    #     port  => '/tmp/mysock.file', # not really a port
    #     proto => 'unix', # will use Net::Server::Proto::UNIXDGRAM
    #     unix_type => 'SOCK_DGRAM',
    # };

    # example 10 #----------------------------------

    $port = "someother.com:20203/ssleay";
    $def_host  = "default-domain.com";
    $def_proto = "tcp";
    $info = Net::Server::Proto->parse_info($port,$def_host,$def_proto);
    # $info = {
    #     host  => 'someother.com',
    #     port  => 20203,
    #     proto => 'ssleay', # will use Net::Server::Proto::SSLEAY
    # };

=head1 LICENCE

Distributed under the same terms as Net::Server

=cut
