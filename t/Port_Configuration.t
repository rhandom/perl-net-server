# -*- Mode: Perl; -*-

=head1 NAME

Port_Configuration.t - Test different ways of specifying the port

=cut

package FooServer;

use strict;
use FindBin qw($Bin);
use lib $Bin;
use NetServerTest qw(prepare_test ok is use_ok diag);
prepare_test({n_tests => 78, plan_only => 1});
#use CGI::Ex::Dump qw(debug);

use_ok('Net::Server');

@FooServer::ISA = qw(Net::Server);

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

my $dump; # poormans dumper - concise but not full bore
$dump = sub {
    my $ref = shift;
    my $ind = shift || '';
    return (!defined $ref) ? 'undef' : ($ref eq '0') ? 0 : ($ref=~/^[1-9]\d{0,12}$/) ? $ref : "'$ref'" if ! ref $ref;
    return "[".join(', ',map {$dump->($_)} @$ref).']' if ref $ref eq 'ARRAY';
    return "{".join(',',map {"\n$ind  $_ => ".$dump->($ref->{$_},"$ind  ")} sort keys %$ref)."\n$ind}";
};

sub p_c { # port check
    my ($pkg, $file, $line) = caller;
    my ($args, $hash, $args_to_new) = @_;
    my $prop = eval { ($args_to_new ? FooServer->new(@$args)->run : FooServer->run(@$args))->{'server'} }
        || do { diag "$@ at line $line"; {} };
    my $got = {_bind => $prop->{'_bind'}};
    if ($hash->{'sock'}) {
        push @{ $got->{'sock'} }, NS_props($_) for @{ $prop->{'sock'} || [] };
    }
    my $result = $dump->($got);
    my $test   = $dump->($hash);
    (my $str = $dump->({ref($args->[0]) eq 'HASH' ? %{$args->[0]} : @$args})) =~ s/\s*\n\s*/ /g;
    $str =~ s/^\{/(/ && $str =~ s/\}$/)/ if ref($args->[0]) ne 'HASH';
    $str .= "  ==>  [ '".join("', '", map {$_->hup_string} @{ $prop->{'sock'} || [] })."' ]";
    $str = ($args_to_new ? 'new' : 'run')." $str";
    if ($result eq $test) {
        ok(1, "$str");
    } else {
        is($result, $test, "$str");
        diag "at line $line";
    }
}

my %class_m;
sub NS_props {
    no strict 'refs';
    my $sock = shift || return {};
    my $pkg  = ref($sock);
    my $m = $class_m{$pkg} ||= {map {$_ => 1} qw(NS_port NS_host NS_proto), grep {/^NS_\w+$/ && defined(&{"${pkg}::$_"})} keys %{"${pkg}::"}};
    return {map {$_ => $sock->$_()} keys %$m};
}

###----------------------------------------------------------------###

p_c([], {
    _bind => [{
        host => '*',
        port => Net::Server::default_port(),
        proto => 'tcp',
    }],
    sock => [{
        NS_host => '*',
        NS_port => Net::Server::default_port(),
        NS_proto => 'TCP',
        NS_family => 0,
    }],
});


p_c([port => 2201], {
    _bind => [{host => '*', port => 2201, proto => 'tcp'}],
});


p_c([port => "localhost:2202"], {
    _bind => [{host => 'localhost', port => 2202, proto => 'tcp'}],
});


p_c([port => "localhost:2202/udp"], {
    _bind => [{host => 'localhost', port => 2202, proto => 'udp'}],
    sock  => [{
        NS_broadcast => undef,
        NS_host => 'localhost',
        NS_port => 2202,
        NS_proto => 'UDP',
        NS_recv_flags => 0,
        NS_recv_len => 4096,
    }],
});


p_c([port => ["localhost:2202/tcp"]], {
    _bind => [{host => 'localhost', port => 2202, proto => 'tcp'}],
});


p_c([port => ["bar.com:2201/udp", "foo.com:2202/tcp"]], {_bind => [
   {host => 'bar.com', port => 2201, proto => 'udp'},
   {host => 'foo.com', port => 2202, proto => 'tcp'},
]});


p_c([port => 2201, host => 'bar.com', proto => 'UDP'], {
    _bind => [{host => 'bar.com', port => 2201, proto => 'UDP'}],
});


p_c([{port => 2201, host => 'bar.com', proto => 'UDP'}], {
    _bind => [{host => 'bar.com', port => 2201, proto => 'UDP'}],
});


p_c([port => 2201, host => 'bar.com', proto => 'UDP'], {
    _bind => [{host => 'bar.com', port => 2201, proto => 'UDP'}],
}, 'new');


p_c([{port => 2201, host => 'bar.com', proto => 'UDP'}], {
    _bind => [{host => 'bar.com', port => 2201, proto => 'UDP'}],
}, 'new');


p_c([port => [2201, "foo.com:2202/tcp"], host => 'bar.com', proto => 'UDP'], {_bind => [
   {host => 'bar.com', port => 2201, proto => 'UDP'},
   {host => 'foo.com', port => 2202, proto => 'tcp'},
]});


__END__

$prop = eval { FooServer->new({port => 2201, host => 'bar.com', proto => 'UDP'})->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'_bind'} } == 1,         "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

###----------------------------------------------------------------###

$prop = eval { FooServer->new(port => 2201, host => 'bar.com', proto => 'UDP')->run->{'server'} };
ok($prop, "Loaded server");
$prop ||= {};
ok(@{ $prop->{'_bind'} } == 1,         "Had 1 configured ports");
ok(@{ $prop->{'sock'} } == 1,          "Had 1 configured socket");
$sock = eval {$prop->{'sock'}->[0]};
ok(eval { $sock->NS_host  eq 'bar.com' }, "Right host");
ok(eval { $sock->NS_port  == 2201 },    "Right port");
ok(eval { $sock->NS_proto eq 'UDP' },   "Right proto");

