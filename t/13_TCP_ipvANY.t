#!/usr/bin/env perl

package Net::Server::Test;
# Test to ensure IPv* listens on both IPv4 (mapped) and IPv6 within a single listener sock.
use strict;
use warnings;
use FindBin qw($Bin);
use lib $Bin;
use NetServerTest qw(prepare_test ok use_ok note skip_without_ipv6);
skip_without_ipv6;
exit 0+!print "1..0 # SKIP Platform does not permit disabling V6ONLY\n" if !Net::Server::Proto->CAN_DISABLE_V6ONLY;
my $IPv4 = "127.0.0.1"; # Should connect to IPv4
my $IPv6 = "::1"; # Should also connect to IPv6
my $env = prepare_test({n_tests => 5, start_port => 20700, n_ports => 1}); # runs three of its own tests

use_ok('Net::Server');
@Net::Server::Test::ISA = qw(Net::Server);

sub accept {
    my $self = shift;
    my $s = scalar @{ $self->{'server'}->{'sock'} };
    my $l = scalar @{ $self->{'server'}->{'_bind'} };
    die "Expected one Dual Stack sock but got [sock=$s] [_bind=$l]" if 1 != $s || 1 != $l;
    $env->{'signal_ready_to_test'}->();
    return $self->SUPER::accept(@_);
}

sub process_request {
    my ($self, $client) = @_;
    my $remote_addr = $client->peerhost;
    print "<$remote_addr> ";
    return $self->SUPER::process_request($client);
}

my $ok = eval {
    local $SIG{'ALRM'} = sub { die "Timeout\n" };
    alarm $env->{'timeout'};
    my $ppid = $$;
    my $pid = fork;
    die "Trouble forking: $!" if ! defined $pid;

    ### parent does the client
    if ($pid) {
        $env->{'block_until_ready_to_test'}->();

        ### connect to child using IPv4
        my $remote = Net::Server::Proto->ipv6_package->new(
            PeerAddr => $IPv4,
            PeerPort => $env->{'ports'}->[0],
            Proto    => 'tcp') or die "IPv4 connection failed to [$IPv4] [$env->{'ports'}->[0]]: [$!] $@";
        my $line = <$remote>;
        note "IPv4 Banner: $line";
        # If CAN_DISABLE_V6ONLY with IPv*, then IPv4 connections should use IPv4-Mapped addresses on a single IPv6 sock:
        die "Didn't get the banner expected: $line" if $line !~ /<::ffff:\Q$IPv4\E>.*Welcome.*Net::Server/i;

        ### connect to child using IPv6
        $remote = Net::Server::Proto->ipv6_package->new(
            PeerAddr => $IPv6,
            PeerPort => $env->{'ports'}->[0],
            Proto    => 'tcp') or die "IPv4 connection failed to [$IPv6] [$env->{'ports'}->[0]]: [$!] $@";

        $line = <$remote>;
        note "IPv6 Banner: $line";
        die "Didn't get the banner expected: $line" if $line !~ /<\Q$IPv6\E>.*Welcome.*Net::Server/;
        print $remote "exit\n";
        return 1;

    ### child does the server
    } else {
        eval {
            open STDERR, ">", "/dev/null";
            local $SIG{ALRM} = sub { die "Timeout" };
            alarm(5);
            Net::Server::Test->run(
                port => "$env->{'ports'}->[0]/tcp",
                host => "*",
                ipv  => "*",
                background => 0,
                setsid => 0,
            );
        } || do {
            note("Trouble running server: $@");
            kill(9, $ppid) && ok(0, "Failed during run of server");
        };
        exit;
    }
    alarm(0);
    return 1;
};
alarm(0);
ok($ok, "Got the correct output from the server") || note("Error: $@");
