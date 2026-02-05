#!/usr/bin/env perl

package Net::Server::Test;
use strict;
use FindBin qw($Bin);
use lib $Bin;
use NetServerTest qw(prepare_test ok use_ok note skip);
my $env = prepare_test({n_tests => 8, start_port => 20200, n_ports => 4}); # runs three of its own tests

if (! eval { require Net::SSLeay }
   ) {
  SKIP: { skip("Cannot load Net::SSleay libraries to test Socket SSL server: $@", 1); };
    exit;
}
if (! eval { require Net::Server::Proto::SSLEAY }) {
    note "Cannot load SSLEAY library on this platform: $@";
  SKIP: { skip("Skipping tests on this platform", 1); };
    exit;
}

require Net::Server;
@Net::Server::Test::ISA = qw(Net::Server);

sub accept {
    my $self = shift;
    exit if $^O eq 'MSWin32' && $self->{'__one_accept_only'}++;
    $env->{'signal_ready_to_test'}->();
    return $self->SUPER::accept(@_);
}

sub process_request {
    my $self = shift;
    my $client = $self->{'server'}->{'client'};
    my $bail = sub { my $why=shift; $why=~s/\s*$//; $why=localtime().": [$$] Server Failure! $why\r\n"; warn $why; print $why; $self->server_close; };

    # Port #0. Default Net::Server STDIN/STDOUT test
    return $self->SUPER::process_request if $client->NS_port == $env->{'ports'}->[0];

    # Port #1. TieHandle / Client EOF test
    if ($client->NS_port == $env->{'ports'}->[1]) {
        print STDOUT "Welcome to $self [$$] TEST PORT1\r\n";
        my $cmd = <STDIN>;
        $cmd =~ y/\r\n//d;
        my $res = syswrite(STDOUT, "RECV1 CMD: $cmd\r\n");
        $res > 0 or return $bail->("1.1: Bad Wrote [$res]");
        0 == sysread(STDIN, $cmd, 100) and $cmd eq '' or return $bail->("1.1: CLIENT NOT EOF: $cmd");
        return;
    }

    # Port #2. read_until / Server EOF test
    if ($client->NS_port == $env->{'ports'}->[2]) {
        print "Welcome to $self [$$] TEST PORT2\r\n";
        my $buf = $client->read_until(100,"\n");
        $buf =~ /^(\w.*?)\s*$/ or return $bail->("2.1: read_until: $buf");
        print "OK GOT1: $1\r\n";
        sleep 1;
        $buf = $client->read_until(100,"\n");
        $buf =~ /^(\w.*?)\s*$/ or return $bail->("2.2: read_until: $buf");
        print "OK GOT2: $1\r\n";
        #close STDOUT; #sleep 1;
        return;
    }

    # Port #3. sysread/syswrite test
    # Read request, echo it back, then exit entire server listener
    my $buf;
    my $res = $client->sysread($buf, 100);
    $res > 0 or return $bail->("3.1: sysread: $buf");
    $client->syswrite($buf);

    # Last test, so close the server
    $self->server_close;
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
        my ($remote,$ctx,$ssl,$line,$rv,$wrote);


        # Port #0. Default Net::Server STDIN/STDOUT test
        $remote = NetServerTest::client_connect(PeerAddr => $env->{'hostname'}, PeerPort => $env->{'ports'}->[0]) or die "Port0: Couldn't connect: $!";
        ok($remote, "Connected to Port #0 $env->{'ports'}->[0]") or die "Port0: Couldn't connect: $!";
        $ctx = Net::SSLeay::CTX_new() or Net::SSLeay::die_now("Failed to create SSL_CTX $!");
        Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
        $ssl = Net::SSLeay::new($ctx) or Net::SSLeay::die_now("Failed to create SSL $!");
        Net::SSLeay::set_fd($ssl, $remote->fileno);
        Net::SSLeay::connect($ssl);
        ($line, $rv) = Net::SSLeay::read($ssl);
        die "Port0.1: Didn't get what was expected: [$rv] ($line)" if $line !~ /Net::Server/;
        note "Port0.1: ($rv) $line";
        $wrote = Net::SSLeay::write($ssl, "quit\n");
        note "Port0.2: ($wrote) written";
        die "Port0.2: Failure? [$wrote]" if $wrote <= 0;
        ($line, $rv) = Net::SSLeay::read($ssl);
        note "Port0.3: ($rv) $line";


        # Port #1. TieHandle / Client EOF test
        $remote = NetServerTest::client_connect(PeerAddr => $env->{'hostname'}, PeerPort => $env->{'ports'}->[1]);
        ok($remote, "Connected to Port #1 $env->{'ports'}->[1]") or die "Port1: Couldn't connect: $!";
        $ctx = Net::SSLeay::CTX_new() or Net::SSLeay::die_now("Failed to create SSL_CTX $!");
        Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
        $ssl = Net::SSLeay::new($ctx) or Net::SSLeay::die_now("Failed to create SSL $!");
        Net::SSLeay::set_fd($ssl, $remote->fileno);
        Net::SSLeay::connect($ssl);
        ($line, $rv) = Net::SSLeay::read($ssl);
        die "Port1.1: Didn't get what was expected: [$rv] ($line)" if $line !~ /Net::Server/ or $rv <= 0;
        note "Port1.1: ($rv) $line";
        $wrote = Net::SSLeay::write($ssl, "sup\n");
        note "Port1.2: ($wrote) written";
        die "Port1.2: Failure? [$wrote]" if $wrote <= 0;
        ($line, $rv) = Net::SSLeay::read($ssl);
        note "Port1.3: ($rv) $line";
        close $remote; # Force Client EOF


        # Port #2. read_until / Server EOF test
        $remote = NetServerTest::client_connect(PeerAddr => $env->{'hostname'}, PeerPort => $env->{'ports'}->[2]);
        ok($remote, "Connected to Port #2 $env->{'ports'}->[2]") or die "Port2: Couldn't connect: $!";
        $ctx = Net::SSLeay::CTX_new() or Net::SSLeay::die_now("Failed to create SSL_CTX $!");
        Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
        $ssl = Net::SSLeay::new($ctx) or Net::SSLeay::die_now("Failed to create SSL $!");
        Net::SSLeay::set_fd($ssl, $remote->fileno);
        Net::SSLeay::connect($ssl);
        ($line, $rv) = Net::SSLeay::read($ssl);
        die "Port2.1: Didn't get what was expected: [$rv] ($line)" if $line !~ /Net::Server/ or $rv <= 0;
        note "Port2.1: ($rv) $line";
        $wrote = Net::SSLeay::write($ssl, "sup!\r\nman!\r\n");
        note "Port2.2: ($wrote) written";
        die "Port2.2: Failure? [$wrote]" if $wrote <= 0;
        ($line, $rv) = Net::SSLeay::read($ssl);
        note "Port2.3: ($rv) $line";
        die "Port2.3: Didn't get what was expected: [$rv] ($line)" if $line !~ /^.*1.*sup/m;
        ($line, $rv) = Net::SSLeay::read($ssl) if $line !~ /^.*2.*man/;
        note "Port2.4: ($rv) $line";
        die "Port2.4: Didn't get what was expected: [$rv] ($line)" if $line !~ /^.*2.*man/m;
        ($line, $rv) = Net::SSLeay::read($ssl);
        die "Port2.5: EOF expected, but got more bytes? [$rv] ($line)" if $line or $rv > 0;


        # Port #3. sysread/syswrite test
        $remote = NetServerTest::client_connect(PeerAddr => $env->{'hostname'}, PeerPort => $env->{'ports'}->[3]);
        ok($remote, "Connected to Port #3 $env->{'ports'}->[3]") or die "Port3: Couldn't connect: $!";
        $ctx = Net::SSLeay::CTX_new() or Net::SSLeay::die_now("Failed to create SSL_CTX $!");
        Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
        $ssl = Net::SSLeay::new($ctx) or Net::SSLeay::die_now("Failed to create SSL $!");
        Net::SSLeay::set_fd($ssl, $remote->fileno);
        Net::SSLeay::connect($ssl);
        $wrote = Net::SSLeay::write($ssl, "foo bar");
        note "Port3.1: ($wrote) written";
        die "Port3.1: Failure? [$wrote]" if $wrote <= 0;
        ($line,$rv) = Net::SSLeay::read($ssl);
        note "Port3.2: ($rv) $line";
        die "Port3.2: Didn't get what was expected: ($line)" if $line ne "foo bar";

        # All tests passed.
        return 1;

    ### child does the server
    } else {
        eval {
            alarm $env->{'timeout'};
            open STDERR, ">", "/dev/null";
            Net::Server::Test->run(
                host  => $env->{'hostname'},
                port  => $env->{'ports'},
                ipv   => $env->{'ipv'},
                proto => 'ssleay',
                background => 0,
                setsid => 0,
                SSL_cert_file => "$Bin/self_signed.crt",
                SSL_key_file  => "$Bin/self_signed.key",
                );
        } || do {
            note("Trouble running server: $@");
            kill(9, $ppid) && ok(0, "Failed during run of server");
        };
        exit;
    }
    alarm(0);
};
alarm(0);
ok($ok, "Got the correct output from the server") || note("Error: $@");
