BEGIN { print "1..5\n" };
BEGIN { $| = 1 }

### load the module
print "not " if ! eval { require Net::Server::HTTP };
print "ok 1 - Loaded Net::Server::HTTP\n";

### test http - don't care about platform
my $fork = 0;
eval {
  my $pid = fork;
  die unless defined $pid; # can't fork
  exit unless $pid;        # can fork, exit child
  $fork = 1;
};
print "not " if ! $fork;
print "ok 2 - We can fork $$ ($@)\n";

### become a new type of server
package Net::Server::Test;
@ISA = qw(Net::Server::HTTP);

use IO::Socket;
local $SIG{ALRM} = sub { die };
my $alarm = 5;

### test and setup pipe
local *READ;
local *WRITE;
my $pipe = 0;
eval {

  ### prepare pipe
  pipe( READ, WRITE );
  READ->autoflush(  1 );
  WRITE->autoflush( 1 );

  ### test pipe
  print WRITE "hi\n";
  die unless scalar(<READ>) eq "hi\n";

  $pipe = 1;
};
print "not " if ! $pipe;
print "ok 3 - We can pipe ($@)\n";


### find some open ports
### This is a departure from previously hard
### coded ports.  Each of the server tests
### will use it's own unique ports to avoid
### reuse problems on some systems.
my $start_port = 20200;
my $num_ports  = 1;
my @ports      = ();
for my $i (0..99){
  my $sock = IO::Socket::INET->new(PeerAddr => 'localhost',
				   PeerPort => ($start_port + $i),
                                   Timeout  => 2,
				   Proto    => 'tcp');
  push @ports, ($start_port + $i) if ! defined $sock;
  last if $num_ports == @ports;
}
print "not " if $num_ports != @ports;
print "ok 4 - got the right number of ports (@ports)\n";

SKIP: {
if ($num_ports != @ports) {
    print "ok 5 # skip Not attempting connections because ports not setup properly\n";
    last SKIP;
}


### extend the accept method a little
### we will use this to signal that
### the server is ready to accept connections
sub accept {
    my $self = shift;
    if ($^O eq 'MSWin32') {
        exit if $self->{__one_accept_only} ++;
    }

    print WRITE "ready!\n";

    return $self->SUPER::accept();
}

sub done { 1 } # force exit after first request


### start up a vanilla server and connect to it
if (! $fork || ! $pipe) {
    print "not ok 5 - no pipe or no fork\n";
} else {
    eval {
        alarm $alarm;

        my $pid = fork;

        ### can't proceed unless we can fork
        die unless defined $pid;

        ### parent does the server
        if ($pid) {

            close STDERR;
            Net::Server::Test->run(port => $ports[0], server_type => 'Single');
            exit;

        ### child does the client - wait for accept to signal we are ready
        } else {

            <READ>; ### wait until the parent accept writes to us

            ### connect to child
            my $remote = IO::Socket::INET->new(PeerAddr => 'localhost',
                                               PeerPort => $ports[0],
                                               Proto    => 'tcp');
            die unless defined $remote;

            print $remote "GET / HTTP/1.0\nFoo: bar\n\n";

            ### sample a line
            my @lines = <$remote>;
            print map {s/\s*$//; "# $_\n"} @lines;
            die unless @lines && $lines[0] =~ m{^HTTP/1.0};

            ### shut down the server
            print "ok 5 - server success\n";
        }


        alarm 0;
    };
    print "not ok 5 - error during server ($@)\n" if $@;
}


}; # end of SKIP
