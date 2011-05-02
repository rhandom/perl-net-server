# -*- perl -*-
#
#  Net::Server::Proto::SSL - Net::Server Protocol module
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

package Net::Server::Proto::SSL;

use strict;
eval { require IO::Socket::SSL; };
$@ && warn "Module IO::Socket::SSL is required for SSL.";
our @ISA = qw(IO::Socket::SSL);

our $VERSION = $Net::Server::VERSION; # done until separated

sub NS_proto { 'SSL' }

sub object {
    my ($class, $default_host, $port, $server) = @_;
    my $prop = $server->{'server'};
    my $host;

    if ($port =~ /^([\w\.\-\*\/]+):(\w+)$/) { # allow for things like "domain.com:80"
        ($host, $port) = ($1, $2);
    } elsif ($port =~ /^(\w+)$/) { # allow for things like "80"
        ($host, $port) = ($default_host, $1);
    } else {
        $server->fatal("Unknown port type \"$port\" under ".__PACKAGE__);
    }

  # read any additional protocol specific arguments
  my @ssl_args = qw(
      SSL_server
      SSL_use_cert
      SSL_verify_mode
      SSL_key_file
      SSL_cert_file
      SSL_ca_path
      SSL_ca_file
      SSL_cipher_list
      SSL_passwd_cb
      SSL_max_getline_length
  );
    my %args = map {$_ => \$prop->{$_}} @ssl_args;
    $server->configure(\%args);

    my $sock = $class->new;
    $sock->NS_host($host);
    $sock->NS_port($port);

    for my $key (@ssl_args) {
        my $val = defined($prop->{$key}) ? $prop->{$key} : $server->can($key) ? $server->$key($host, $port, 'SSL') : undef;
        $sock->$key($val);
    }

    return $sock;
}

sub log_connect {
    my ($sock, $server) = @_;
    $server->log(2, "Binding to ".$sock->NS_proto." port ".$sock->NS_port." on host ".$sock->NS_host);
}

sub connect {
    my ($sock, $server) = @_;
    my $prop = $server->{'server'};
    my $host = $sock->NS_host;
    my $port = $sock->NS_port;

    my %args = (
        LocalPort => $port,
        Proto     => 'tcp',
        Listen    => $prop->{'listen'},
        ReuseAddr => 1, Reuse => 1,
    );
    $args{'LocalAddr'} = $host if $host !~ /\*/; # what local address (* is all)
    $args{$_} = $prop->{$_} for grep {/^SSL_/} keys %$prop;

    $sock->SUPER::configure(\%args) or $server->fatal("Can't connect to SSL port $port on $host [$!]");
}

sub reconnect { # after a sig HUP
    my ($sock, $fd, $server) = @_;
    $sock->fdopen($fd, 'w') or $server->fatal("Error opening to file descriptor ($fd) [$!]");
}

sub accept {
    my $sock = shift;
    if (wantarray) {
        my ($client, $peername) = $sock->SUPER::accept();
        bless $client, ref($sock);
        return ($client, $peername);
    } else {
        my $client = $sock->SUPER::accept();
        bless $client, ref($sock);
        return $client;
    }
}

sub hup_string {
    my $sock = shift;
    return join "|", $sock->NS_host, $sock->NS_port, $sock->NS_proto;
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

1;

=head1 NAME

Net::Server::Proto::SSL - Net::Server SSL protocol (deprecated - use Net::Server::Proto::SSLEAY instead).

=head1 SYNOPSIS

This module is mostly deprecated - you will want to look at Net::Server::Proto::SSLEAY instead.

See L<Net::Server::Proto>.
See L<Net::Server::Proto::SSLEAY>.

=head1 DESCRIPTION

This original SSL module was experimental.  It has been superceeded by
Net::Server::Proto::SSLEAY If anybody has any successes or ideas for
improvment under SSL, please email <paul@seamons.com>.

Protocol module for Net::Server.  This module implements a
secure socket layer over tcp (also known as SSL).
See L<Net::Server::Proto>.

There is a limit inherent from using IO::Socket::SSL,
namely that only one SSL connection can be maintained by
Net::Server.  However, Net::Server should also be able to
maintain any number of TCP, UDP, or UNIX connections in
addition to the one SSL connection.

Additionally, getline support is very limited and writing directly to
STDOUT will not work.  This is entirely dependent upon the
implementation of IO::Socket::SSL.  getline may work but the client is
not copied to STDOUT under SSL.  It is suggested that clients sysread
and syswrite to the client handle (located in
$self->{'server'}->{'client'} or passed to the process_request subroutine
as the first argument).

=head1 PARAMETERS

In addition to the normal Net::Server parameters, any of the
SSL parameters from IO::Socket::SSL may also be specified.
See L<IO::Socket::SSL> for information on setting this up.

=head1 BUGS

Christopher A Bongaarts pointed out that if the SSL negotiation is
slow then the server won't be accepting for that period of time
(because the locking of accept is around both the socket accept and
the SSL negotiation).  This means that as it stands now the SSL
implementation is susceptible to DOS attacks.  To fix this will
require deviding up the accept call a little bit more finely which may
not yet be possible with IO::Socket::SSL.  Any ideas or patches on
this bug are welcome.

=head1 LICENCE

Distributed under the same terms as Net::Server

=head1 THANKS

Thanks to Vadim for pointing out the IO::Socket::SSL accept
was returning objects blessed into the wrong class.

=cut
