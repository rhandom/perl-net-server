use strict;
use IO::Socket;
require Test::More;

my %env = map {/NET_SERVER_TEST_(\w+)/; lc($1) => $ENV{$_}} grep {/^NET_SERVER_TEST_\w+$/} keys %ENV;
$env{'hostname'} ||= 'localhost';
$env{'timeout'}  ||= 5;
sub nst_env { \%env }

# most of our tests need forking, a certain number of ports, and some pipes
sub nst_prepare_test {
    my $args = shift || {};
    my $N = $args->{'n_tests'} || die "Missing n_tests";

    Test::More::ok(nst_can_fork(), "Can fork on this platform") || do { SKIP { skip("Fork doesn't work on this platform", $N - 2) }; exit; };

    my $ports = $env{'ports'} = nst_get_ports($args);
    Test::More::ok(+@$ports, "Got needed ports") || do { SKIP { skip("Couldn't get the needed ports for testing", $N - 3) }; exit };

    pipe(NST_READ, NST_WRITE);
    NST_READ->autoflush(1);
    NST_WRITE->autoflush(1);
    print NST_WRITE "hi\n";
    Test::More::is(scalar(<NST_READ>), "hi\n", "Pipe works") || do { SKIP { skip ("Couldn't use working pipe", $N - 4) }; exit };

    $env{'block_until_ready_to_test'} = sub { scalar <NST_READ>; };
    $env{'signal_ready_to_test'}      = sub { print NST_WRITE "ready\n"; };

    return \%env;
}


sub nst_can_fork {
    return eval {
        my $pid = fork;
        die "Trouble while forking" unless defined $pid; # can't fork
        exit unless $pid; # can fork, exit child
        1;
    };
}

sub nst_get_ports {
    my $args = shift;
    my $start_port = $args->{'start_port'} || die "Missing start_port";
    my $n          = $args->{'n_ports'}    || die "Missing n_ports";
    my @ports;
    eval {
        local $SIG{'ALRM'} = sub { die };
        alarm $env{'timeout'};
        for my $port ($start_port .. $start_port + 99){
            my $serv = IO::Socket::INET->new(LocalAddr => $env{'hostname'},
                                             LocalPort => $port,
                                             Timeout   => 2,
                                             Listen    => 1,
                                             ReuseAddr => 1, Reuse => 1,
                ) || do { warn "Couldn't open server socket on port $port: $!\n" if $env{'trace'}; next };
            my $client = IO::Socket::INET->new(PeerAddr => $env{'hostname'},
                                               PeerPort => $port,
                                               Timeout  => 2,
                ) || do { warn "Couldn't open client socket on port $port: $!\n" if $env{'trace'}; next };
            my $sock = $serv->accept || do { warn "Didn't accept properly on server: $!" if $env{'trace'}; next };
            $sock->autoflush(1);
            print $sock "hi from server\n";
            $client->autoflush(1);
            print $client "hi from client\n";
            next if <$sock>   !~ /^hi from client/;
            next if <$client> !~ /^hi from server/;
            $client->close;
            $sock->close;
            push @ports, $port;
            last if @ports == $n;
        }
        alarm(0);
    };
    die "Number of ports didn't match (@ports) != $n ($@)" if @ports < $n;
    return \@ports;
}

1;
