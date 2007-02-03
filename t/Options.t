# -*- Mode: Perl; -*-

=head1 NAME

Options.t - Test commandline options and such

=cut

package FooServer;

use vars qw(@ISA);
use strict;
use Test::More tests => 64;
#use CGI::Ex::Dump qw(debug);

use_ok('Net::Server');

@ISA = qw(Net::Server);

### override-able options for this package
sub options {
  my $self     = shift;
  my $prop     = $self->{'server'};
  my $template = shift;

  ### setup options in the parent classes
  $self->SUPER::options($template);

  $prop->{'my_option'} = undef;
  $template->{'my_option'} = \ $prop->{'my_option'};

  $prop->{'an_arrayref_item'} ||= [];
  $template->{'an_arrayref_item'} = $prop->{'an_arrayref_item'};
}

### provide default values
sub default_values {
    return {
        group => 'defaultgroup',
        allow => ['127.0.0.1', '192.169.0.1'],
    };
}

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
ok(@{ $prop->{'port'} } == 1,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(port => [2201, 2202])->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 2,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");
ok($prop->{'port'}->[1] == 2202, "Right port");

###----------------------------------------------------------------###

$prop = eval { FooServer->run({port => 2201})->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");

###----------------------------------------------------------------###

$prop = eval { FooServer->new(port => 2201)->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");

###----------------------------------------------------------------###

$prop = eval { FooServer->new({port => 2201})->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");

###----------------------------------------------------------------###

$prop = eval { local @ARGV = ('--port', '2201'); FooServer->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 1,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");

###----------------------------------------------------------------###

$prop = eval { local @ARGV = ('--port', '2201', '--port=2202'); FooServer->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 2,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 2201, "Right port");
ok($prop->{'port'}->[1] == 2202, "Right port");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(conf_file => __FILE__.'.conf')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'port'} } == 3,    "Had 1 configured ports");
ok($prop->{'port'}->[0] == 5401, "Right port");
ok($prop->{'port'}->[1] == 5402, "Right port");
ok($prop->{'port'}->[2] == 5403, "Right port");
ok($prop->{'user'} eq 'foo',     "Right user");

###----------------------------------------------------------------###

$prop = eval { local @ARGV = ('--user=cmdline'); FooServer->run(conf_file => __FILE__.'.conf', user => 'runargs')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'user'} eq 'cmdline', "Right user \"$prop->{'user'}\"");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(conf_file => __FILE__.'.conf', user => 'runargs')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'user'} eq 'runargs', "Right user \"$prop->{'user'}\"");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(my_option => 'wow')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'my_option'} eq 'wow', 'Could use custom options');

###----------------------------------------------------------------###

$prop = eval { FooServer->run(an_arrayref_item => 'wow')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'an_arrayref_item'} } == 1,     "Had 1 configured custom array option");
ok($prop->{'an_arrayref_item'}->[0] eq 'wow', "Right value");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(conf_file => __FILE__.'.conf', user => 'runargs')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'my_option'} eq 'bar', "Right my_option \"$prop->{'my_option'}\"");
ok(@{ $prop->{'an_arrayref_item'} } == 3,     "Had 3 configured custom array option");
ok($prop->{'an_arrayref_item'}->[0] eq 'one', "Right value");
ok($prop->{'an_arrayref_item'}->[1] eq 'three', "Right value");
ok($prop->{'an_arrayref_item'}->[2] eq 'two', "Right value");

###----------------------------------------------------------------###

$prop = eval { local @ARGV = ('--group=cmdline'); FooServer->run(conf_file => __FILE__.'.conf', group => 'runargs')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'group'} eq 'cmdline', "Right user \"$prop->{'group'}\"");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(conf_file => __FILE__.'.conf', group => 'runargs')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'group'} eq 'runargs', "Right user \"$prop->{'group'}\"");

###----------------------------------------------------------------###

$prop = eval { FooServer->run(conf_file => __FILE__.'.conf')->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'group'} eq 'confgroup', "Right user \"$prop->{'group'}\"");

###----------------------------------------------------------------###

$prop = eval { FooServer->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok($prop->{'group'} eq 'defaultgroup', "Right user \"$prop->{'group'}\"");
ok(@{ $prop->{'allow'} } == 2, "Defaults for allow are set also");

