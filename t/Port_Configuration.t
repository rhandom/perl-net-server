# -*- Mode: Perl; -*-

=head1 NAME

Port_Configuration.t - Test different ways of specifying the port

=cut

package FooServer;

use vars qw(@ISA);
use strict;
use Test::More tests => 78;
#use CGI::Ex::Dump qw(debug);

use_ok('Net::Server');

@ISA = qw(Net::Server);

#sub proto_object {
#    my ($self, $host, $port, $proto) = @_;
#    #debug $host, $port, $proto;
#    #return $self->SUPER::proto_object($host, $port, $proto);
#    return "Blah";
#}

### override these to make run not run
### this will allow all configuration cycles to be run
sub bind {}
sub post_bind {}
sub loop {}
sub log {}
sub server_close {
    my $self = shift;
    return $self;
}

###----------------------------------------------------------------###

my $obj = eval { FooServer->new };
ok($obj, "Got an object ($@)");

my $server = eval { FooServer->run };
ok($server, "Got a server ($@)");
my $prop = eval { $server->{'server'} } || {};
ok($prop->{'log_level'} == 2,  "Correct default log_level");
ok($prop->{'log_file'}  eq "", "Correct default log_file");
ok(! $prop->{'user'},          "Correct default user");
ok(! $prop->{'group'},         "Correct default group");
ok(@{ $prop->{'port'} } == 1,         "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,         "Had 1 configured socket");
my $sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq '*' },   "Right host");
ok(eval { $sock->NS_port  == 20203 }, "Right port");
ok(eval { $sock->NS_proto eq 'TCP' }, "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => 2201)->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq '*' },     "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'TCP' },   "Right proto");


###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => "localhost:2202")->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'localhost' }, "Right host");
ok(eval { $sock->NS_port  == 2202 },    "Right port");
ok(eval { $sock->NS_proto eq 'TCP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => "localhost:2202/udp")->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'localhost' }, "Right host");
ok(eval { $sock->NS_port  == 2202 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => ["localhost:2202/tcp"])->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'localhost' }, "Right host");
ok(eval { $sock->NS_port  == 2202 },    "Right port");
ok(eval { $sock->NS_proto eq 'TCP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => ["bar.com:2201/udp", "foo.com:2202/tcp"])->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 2,          "Had 2 configured ports");
ok(@{ $prop->{'sock'} } == 2,          "Had 2 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");
$sock = eval {$prop->{'sock'}->[1]};
ok(eval { $sock->NS_host  eq 'foo.com' }, "Right host");
ok(eval { $sock->NS_port  == 2202 },    "Right port");
ok(eval { $sock->NS_proto eq 'TCP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => [2201, "foo.com:2202/tcp"], host => 'bar.com', proto => 'UDP')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 2,          "Had 2 configured ports");
ok(@{ $prop->{'sock'} } == 2,          "Had 2 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");
$sock = eval {$prop->{'sock'}->[1]};
ok(eval { $sock->NS_host  eq 'foo.com' }, "Right host");
ok(eval { $sock->NS_port  == 2202 },    "Right port");
ok(eval { $sock->NS_proto eq 'TCP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => 2201, host => 'bar.com', proto => 'UDP')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->run({port => 2201, host => 'bar.com', proto => 'UDP'})->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->new({port => 2201, host => 'bar.com', proto => 'UDP'})->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->new(port => 2201, host => 'bar.com', proto => 'UDP')->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,          "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

