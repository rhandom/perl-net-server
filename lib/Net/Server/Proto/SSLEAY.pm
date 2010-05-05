# -*- perl -*-
#
#  Net::Server::Proto::SSLEAY - Net::Server Protocol module
#
#  $Id$
#
#  Copyright (C) 2010
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

package Net::Server::Proto::SSLEAY;

use strict;
use vars qw($VERSION $AUTOLOAD @ISA);
use IO::Socket::INET;
use Fcntl ();
use Errno ();
use Socket ();

BEGIN {
    eval { require Net::SSLeay };
    $@ && warn "Module Net::SSLeay is required for SSLeay.";
    # Net::SSLeay gets mad if we call these multiple times - the question is - who will call them multiple times?
    for my $sub (qw(load_error_strings SSLeay_add_ssl_algorithms ENGINE_load_builtin_engines ENGINE_register_all_complete randomize)) {
        Net::SSLeay->can($sub)->();
    }
}

$VERSION = $Net::Server::VERSION; # done until separated
@ISA = qw(IO::Socket::INET);

sub object {
    my $type  = shift;
    my $class = ref($type) || $type || __PACKAGE__;

    my ($default_host,$port,$server) = @_;
    my $prop = $server->{'server'};
    my $host;

    if ($port =~ m/^([\w\.\-\*\/]+):(\w+)$/) { # allow for things like "domain.com:80"
        ($host, $port) = ($1, $2);
    }
    elsif ($port =~ /^(\w+)$/) { # allow for things like "80"
        ($host, $port) = ($default_host, $1);
    }
    else {
        $server->fatal("Undeterminate port \"$port\" under ".__PACKAGE__);
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
        SSL_error_callback
        SSL_max_getline_length
    );
    my %args;
    $args{$_} = \$prop->{$_} for @ssl_args;
    $server->configure(\%args);

    my $sock = $class->new;
    $sock->NS_host($host);
    $sock->NS_port($port);
    $sock->NS_proto('SSLEAY');

    for my $key (@ssl_args) {
        my $val = defined($prop->{$key}) ? $prop->{$key} : $server->can($key) ? $server->$key($host, $port, 'SSLEAY') : undef;
        $sock->$key($val);
    }

    return $sock;
}

sub log_connect {
    my $sock = shift;
    my $server = shift;
    my $host   = $sock->NS_host;
    my $port   = $sock->NS_port;
    my $proto  = $sock->NS_proto;
    $server->log(2,"Binding to $proto port $port on host $host\n");
}

###----------------------------------------------------------------###

sub connect { # connect the first time
    my $sock   = shift;
    my $server = shift;
    my $prop   = $server->{'server'};

    my $host  = $sock->NS_host;
    my $port  = $sock->NS_port;

    my %args;
    $args{'LocalPort'} = $port;
    $args{'Proto'}     = 'tcp';
    $args{'LocalAddr'} = $host if $host !~ /\*/; # * is all
    $args{'Listen'}    = $prop->{'listen'};
    $args{'Reuse'}     = 1;

    $sock->SUPER::configure(\%args) || $server->fatal("Can't connect to SSL port $port on $host [$!]");
    $server->fatal("Bad sock [$!]!".caller()) if ! $sock;

    if ($port == 0 && ($port = $sock->sockport)) {
        $sock->NS_port($port);
        $server->log(2,"Bound to auto-assigned port $port");
    }

    $sock->bind_SSL($server);
}

sub reconnect { # connect on a sig -HUP
    my ($sock, $fd, $server) = @_;
    my $resp = $sock->fdopen( $fd, 'w' ) || $server->fatal("Error opening to file descriptor ($fd) [$!]");
    $sock->bind_SSL($server);
    return $resp;
}

sub bind_SSL {
    my ($sock, $server) = @_;
    my $ctx = Net::SSLeay::CTX_new();  $sock->SSLeay_check_fatal("SSLeay bind_SSL CTX_new");

    Net::SSLeay::CTX_set_options($ctx, Net::SSLeay::OP_ALL());  $sock->SSLeay_check_fatal("SSLeay bind_SSL CTX_set_options");

    # 0x1:  SSL_MODE_ENABLE_PARTIAL_WRITE
    # 0x10: SSL_MODE_RELEASE_BUFFERS (ignored before OpenSSL v1.0.0)
    Net::SSLeay::CTX_set_mode($ctx, 0x11);  $sock->SSLeay_check_fatal("SSLeay bind_SSL CTX_set_mode");

    # Load certificate. This will prompt for a password if necessary.
    my $file_key  = $sock->SSL_key_file  || die "SSLeay missing SSL_key_file.\n";
    my $file_cert = $sock->SSL_cert_file || die "SSLeay missing SSL_cert_file.\n";
    Net::SSLeay::CTX_use_RSAPrivateKey_file($ctx, $file_key,  Net::SSLeay::FILETYPE_PEM());  $sock->SSLeay_check_fatal("SSLeay bind_SSL CTX_use_RSAPrivateKey_file");
    Net::SSLeay::CTX_use_certificate_file(  $ctx, $file_cert, Net::SSLeay::FILETYPE_PEM());  $sock->SSLeay_check_fatal("SSLeay bind_SSL CTX_use_certificate_file");
    $sock->SSLeay_context($ctx);
}

sub close {
    my $sock = shift;
    if ($sock->SSLeay_is_client) {
        Net::SSLeay::free($sock->SSLeay);
    } else {
        Net::SSLeay::CTX_free($sock->SSLeay_context);
    }
    $sock->SSLeay_check_fatal("SSLeay close free");
    return $sock->SUPER::close(@_);
}

sub accept {
    my $sock = shift;
    my $client = $sock->SUPER::accept;
    if (defined $client) {
        $client->NS_proto($sock->NS_proto);
        $client->SSLeay_context($sock->SSLeay_context);
        $client->SSLeay_is_client(1);
    }

    return $client;
}

sub SSLeay {
    my $client = shift;

    if (! exists ${*$client}{'SSLeay'}) {
        die "SSLeay refusing to accept on non-client socket" if !$client->SSLeay_is_client;

        $client->autoflush(1);

        my $f = fcntl($client, Fcntl::F_GETFL(), 0)                || die "SSLeay - fcntl get: $!\n";
        fcntl($client, Fcntl::F_SETFL(), $f | Fcntl::O_NONBLOCK()) || die "SSLeay - fcntl set: $!\n";

        my $ssl = Net::SSLeay::new($client->SSLeay_context);  $client->SSLeay_check_fatal("SSLeay new");
        Net::SSLeay::set_fd($ssl, $client->fileno);           $client->SSLeay_check_fatal("SSLeay set_fd");
        Net::SSLeay::accept($ssl);                            $client->SSLeay_check_fatal("SSLeay accept");
        ${*$client}{'SSLeay'} = $ssl;
    }

    return ${*$client}{'SSLeay'};
}

sub SSLeay_check_fatal {
    my ($client, $msg) = @_;
    if (my $err = $client->SSLeay_check_error($msg, 1)) {
        my ($file, $pkg, $line) = caller;
        die "$msg at $file line $line\n  ".join('  ', @$err);
    }
}

sub SSLeay_check_error {
    my ($client, $msg, $fatal) = @_;
    my @err;
    while (my $n = Net::SSLeay::ERR_get_error()) {
        push @err, "$n. ". Net::SSLeay::ERR_error_string($n) ."\n";
    }
    if (@err) {
        my $cb = $client->SSL_error_callback;
        $cb->($client, $msg, \@err, ($fatal ? 'is_fatal' : ())) if $cb;
        return \@err;
    }
    return;
}


###----------------------------------------------------------------###

sub read_until {
    my ($client, $bytes, $end_qr, $non_greedy) = @_;

    my $ssl = $client->SSLeay;
    my $content = ${*$client}{'SSLeay_buffer'};
    $content = '' if ! defined $content;
    my $ok = 0;

    # the rough outline for this loop came from http://devpit.org/wiki/OpenSSL_with_nonblocking_sockets_%28in_Perl%29
    OUTER: while (1) {
        if (!length($content)) {
        }
        elsif (defined($bytes) && length($content) >= $bytes) {
            ${*$client}{'SSLeay_buffer'} = substr($content, $bytes, length($content), '');
            $ok = 2;
            last;
        }
        elsif (defined($end_qr) && $content =~ m/$end_qr/g) {
            my $n = pos($content);
            ${*$client}{'SSLeay_buffer'} = substr($content, $n, length($content), '');
            $ok = 1;
            last;
        }

        vec(my $vec = '', $client->fileno, 1) = 1;
        select($vec, undef, undef, undef);

        my $n_empty = 0;
        while (1) {
            # 16384 is the maximum amount read() can return
            my $n = 16384;
            $n -= ($bytes - length($content)) if $non_greedy && ($bytes - length($content)) < $n;
            my $buf = Net::SSLeay::read($ssl, 16384); # read the most we can - continue reading until the buffer won't read any more
            if ($client->SSLeay_check_error('SSLeay read_until read')) {
                last OUTER;
            }
            die "SSLeay read_until: $!\n" if ! defined($buf) && !$!{EAGAIN} && !$!{EINTR} && !$!{ENOBUFS};
            last if ! defined($buf);
            if (!length($buf)) {
                last OUTER if !length($buf) && $n_empty++;
            }
            else {
                $content .= $buf;
                if ($non_greedy && length($content) == $bytes) {
                    $ok = 3;
                    last;
                }
            }
        }
    }
    return wantarray ? ($ok, $content) : $content;
}

sub read {
    my ($client, $buf, $size, $offset) = @_;
    my ($ok, $read) = $client->read_until($size, undef, 1);
    substr($_[1], $offset || 0, defined($buf) ? length($buf) : 0, $read);
    return length $read;
}

sub getline {
    my $client = shift;
    my ($ok, $line) = $client->read_until($client->SSL_max_getline_length, $/);
    return $line;
}

sub getlines {
    my $client = shift;
    my @lines;
    while (1) {
        my ($ok, $line) = $client->read_until($client->SSL_max_getline_length, $/);
        push @lines, $line;
        last if $ok != 1;
    }
    return @lines;
}

sub print {
    my $client = shift;
    my $buf    = @_ == 1 ? $_[0] : join('', @_);
    my $ssl    = $client->SSLeay;
    while (length $buf) {
        vec(my $vec = '', $client->fileno, 1) = 1;
        select(undef, $vec, undef, undef);

        my $write = Net::SSLeay::write($ssl, $buf);
        return 0 if $client->SSLeay_check_error('SSLeay write');
        die "SSLeay print: $!\n" if $write == -1 && !$!{EAGAIN} && !$!{EINTR} && !$!{ENOBUFS};
        substr($buf, 0, $write, "") if $write > 0;
    }
    return 1;
}

sub printf {
    my $client = shift;
    $client->print(sprintf(shift, @_));
}

sub say {
    my $client = shift;
    $client->print(@_, "\n");
}

sub write {
    my $client = shift;
    my $buf    = shift;
    $buf = substr($buf, $_[1] || 0, $_[0]) if @_;
    $client->print($buf);
}

sub sysread  { die "sysread is not supported by Net::Server::Proto::SSLEAY" }
sub syswrite { die "syswrite is not supported by Net::Server::Proto::SSLEAY" }

###----------------------------------------------------------------###

sub hup_string {
    my $sock = shift;
    return join "|", map{$sock->$_()} qw(NS_host NS_port NS_proto);
}

sub show {
    my $sock = shift;
    my $t = "Ref = \"" .ref($sock) . "\"\n";
    foreach my $prop ( qw(NS_proto NS_port NS_host SSLeay_context SSLeay_is_client) ){
        $t .= "  $prop = \"" .$sock->$prop()."\"\n";
    }
    return $t;
}

sub AUTOLOAD {
    my $sock = shift;
    my $prop = $AUTOLOAD =~ /::([^:]+)$/ ? $1 : die "Missing property in AUTOLOAD.";
    die "Unknown method or property [$prop]"
        if $prop !~ /^(NS_proto|NS_port|NS_host|SSLeay_context|SSLeay_is_client|SSL_\w+)$/;

    no strict 'refs';
    *{__PACKAGE__."::${prop}"} = sub {
        my $sock = shift;
        if (@_) {
            ${*$sock}{$prop} = shift;
            return delete ${*$sock}{$prop} if ! defined ${*$sock}{$prop};
        } else {
            return ${*$sock}{$prop};
        }
    };
    return $sock->$prop(@_);
}

sub tie_stdout { 1 }

1;

=head1 NAME

Net::Server::Proto::SSLEAY - Custom Net::Server SSL protocol handler based on Net::SSLeay directly.

=head1 SYNOPSIS

See L<Net::Server::Proto>.

=head1 DESCRIPTION

This is considered alpha level.  This module hasn't gone through use in production environments
to the degree that the other protocol handlers have.  If anybody has any successes or ideas for
improvment under SSLEAY, please email <paul@seamons.com>.

Protocol module for Net::Server.  This module implements a
secure socket layer over tcp (also known as SSL).
See L<Net::Server::Proto>.

=head1 PARAMETERS

Currently there is support for the following:

=over 4

=item C<SSL_cert_file>

Full path to the certificate file to be used for this server.  Should be in PEM format.

=item C<SSL_key_file>

Full path to the key file to be used for this server.  Should be in PEM format.

=item C<SSL_max_getline_length>

Used during getline to only read until this many bytes are found.  Default is undef which
means unlimited.

=item C<SSL_error_callback>

Should be a code ref that will be called whenever error conditions are encountered.  It passes a source message
and an arrayref of the errors.

=back

I'll add support for more as patches come in.

=head1 METHODS

This module implements most of the common file handle operations.  There are some additions though:

=over 4

=item C<read_until>

Takes bytes and match qr.  If bytes is defined - it will read until
that many bytes are found.  If match qr is defined, it will read until
the buffer matches that qr.  If both are undefined, it will read until
there is nothing left to read.

=back

=head1 BUGS

There are probably many.

=head1 LICENCE

Distributed under the same terms as Net::Server

=head1 THANKS

Thanks to Bilbo at
http://devpit.org/wiki/OpenSSL_with_nonblocking_sockets_%28in_Perl%29
for documenting a more reliable way of accepting and reading SSL connections.

=cut
