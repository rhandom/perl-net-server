# -*- perl -*-

### become a new type of server
package Net::Server::Test;
use Test;

BEGIN { $| = 1; plan tests => 4; $success = 0; }
END { ok 0 unless $success; }

### load the module
use Net::Server::Multiplex;
use IO::Socket;
ok 1;

@ISA = qw(Net::Server::Multiplex);
local $SIG{ALRM} = sub { die };
my $alarm = 15;
alarm $alarm;

local *READ;
local *WRITE;

### Make post_bind_hook notify the client that
### the server is ready to accept connections.
sub post_bind_hook {
  print WRITE "ready!\n";
  close WRITE;
}

sub mux_connection {
  my $self = shift;
  shift; shift; # These two args are boring
  print "Welcome to \"".ref($self)."\" ($$)\n";
}

sub mux_input {
  my $self = shift;
  my $mux  = shift;
  my $fh   = shift;
  my $data = shift;  # Scalar reference to the input

  # Process each line in the input, leaving partial lines
  # in the input buffer
  while ($$data =~ s/^(.*?\n)//) {
    $_ = $1;
    s/\r?\n$//;

    print ref($self),":$$: You said \"$_\"\r\n";
    $self->log(5,$_); # very verbose log

    if( /get (\w+)/ ){
      print "$1: $self->{net_server}->{server}->{$1}\r\n";
    }

    if( /exit/ ){ $self->{net_server}->{mux}->endloop; }
  }
}

### prepare pipe
pipe( READ, WRITE );
READ->autoflush(  1 );
WRITE->autoflush( 1 );

### test pipe
print WRITE "hi\n";
die unless scalar(<READ>) eq "hi\n";
ok 1;

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
				   Proto    => 'tcp');
  push @ports, ($start_port + $i) if ! defined $sock;
  last if $num_ports == @ports;
}
ok ( $num_ports == @ports );

### start up a vanilla server and connect to it
my $pid = fork;

### can't proceed unless we can fork
die unless defined $pid;

### parent does the client
if( $pid ){

  <READ>; ### wait until the child writes to us

  ### connect to child
  my $remote = IO::Socket::INET->new(PeerAddr => 'localhost',
                                     PeerPort => $ports[0],
                                     Proto    => 'tcp');
  die unless defined $remote;

  ### sample a line
  my $line = <$remote>;
  die unless $line =~ /Net::Server/;

  ### shut down the server
  print $remote "exit\n";
  close ($remote);

  $success = 1;
  ok 1;

}else{ ### child does the server

  $success = 1;
  close STDERR;
  __PACKAGE__->run(port => $ports[0],
                   setsid => 1,
                   );
  exit;
}
