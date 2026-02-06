#!/usr/bin/env perl

package Net::Server::Test;
# Test ipv6_package with FakeWrapper3 for Net::Server::IP
use strict;
use warnings;
use FindBin qw($Bin);
use lib $Bin;
use NetServerTest qw(prepare_test ok use_ok note);
exit 0+!print "1..0 # SKIP IPv6 is not supported\n" if !grep {-r "$_/IO/Socket/IP.pm" or -r "$_/IO/Socket/INET6.pm"} @INC;
my $pkg = "FakeWrapper3"; # Net::Server::IP
my $IPv6 = "::1"; # Should connect to IPv6
$ENV{NET_SERVER_TEST_HOSTNAME} ||= "127.0.0.1"; # Fake IPv4 to prevent prepare_test from pre-loading ipv6_package
my $env = prepare_test({n_tests => 5, start_port => 20700, n_ports => 1}); # runs three of its own tests

use_ok('Net::Server');
@Net::Server::Test::ISA = qw(Net::Server);

sub accept {
    $env->{'signal_ready_to_test'}->();
    return shift->SUPER::accept(@_);
}

sub process_request {
    my ($self, $client) = @_;
    # Just make sure falls back to any valid IPv6 module if Super Class was attempted
    my $proof = $client->peerhost eq $IPv6 ? "SUCCESS" : "FAILURE";
    print $client "$proof IPv6-Package Tester ".__FILE__." |CLIENT=$client| ";
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

        ### connect to child using IPv6
        my $remote = Net::Server::Proto->ipv6_package->new(
            PeerAddr => $IPv6,
            PeerPort => $env->{'ports'}->[0],
            Proto    => 'tcp') or die "IPv6 connection failed to [$IPv6] [$env->{'ports'}->[0]]: [$!] $@";

        my $line = <$remote>;
        note "Banner: $line";
        print $remote "exit\n";
        die "Didn't get the type of line we were expecting: ($line)" if $line !~ /SUCCESS.*Welcome/;
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
                ipv  => "6",
                background => 0,
                setsid => 0,
                ipv6_package => $pkg,
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
