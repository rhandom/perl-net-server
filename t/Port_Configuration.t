# -*- Mode: Perl; -*-

=head1 NAME

Port_Configuration.t - Test different ways of specifying the port

=cut

package FooServer;

use strict;
use FindBin qw($Bin);
use lib $Bin;
use NetServerTest qw(prepare_test ok is use_ok diag skip);
prepare_test({n_tests => 30, plan_only => 1});
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
sub fatal {
    my ($self, $msg) = @_;
    die $msg;
}
sub SSL_cert_file { 'somecert' }

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
#    use CGI::Ex::Dump qw(debug);
#    debug $prop;
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
    if ($result eq $test && $str !~ /\|\|/) {
        ok(1, "$str");
    } else {
        is($result, $test, "$str");
        diag "at line $line";
        exit;
    }
}

my %class_m;
sub NS_props {
    no strict 'refs';
    my $sock = shift || return {};
    my $pkg  = ref($sock);
    my $m = $class_m{$pkg} ||= {map {$_ => 1} qw(NS_port NS_host NS_proto), grep {/^(?:SSL|NS)_\w+$/ && defined(&{"${pkg}::$_"})} keys %{"${pkg}::"}};
    return {map {$_ => $sock->$_()} keys %$m};
}

###----------------------------------------------------------------###
# tcp, udp

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
        NS_listen => eval { Socket::SOMAXCONN() },
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

p_c([port => 2202, listen => 5], {
    _bind => [{host => '*', port => 2202, proto => 'tcp'}],
    sock  => [{
        NS_host => '*',
        NS_port => 2202,
        NS_proto => 'TCP',
        NS_listen => 5,
        NS_family => 0,
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


p_c([{port => 2201, host => 'bar.com', proto => 'UDP', udp_recv_len => 400}], {
    _bind => [{host => 'bar.com', port => 2201, proto => 'UDP'}],
    sock  => [{NS_host => 'bar.com', NS_port => 2201, NS_proto => 'UDP', NS_recv_len => 400, NS_recv_flags => 0, NS_broadcast => undef}],
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


p_c([port => ["localhost|2202|tcp"]], {
    _bind => [{host => 'localhost', port => 2202, proto => 'tcp'}],
});


p_c([port => ["localhost,2202,tcp"]], {
    _bind => [{host => 'localhost', port => 2202, proto => 'tcp'}],
});


p_c([port => ["localhost,2202,Net::Server::Proto::TCP"]], {
    _bind => [{host => 'localhost', port => 2202, proto => 'Net::Server::Proto::TCP'}],
});


p_c([port => [{port => 2201}]], {
    _bind => [{host => '*', port => 2201, proto => 'tcp'}],
});


p_c([port => [{port => 2201, host => 'foo.com', proto => 'udp'}]], {
    _bind => [{host => 'foo.com', port => 2201, proto => 'udp'}],
});


p_c([port => [{port => 2201}], host => 'foo.com', proto => 'udp'], {
    _bind => [{host => 'foo.com', port => 2201, proto => 'udp'}],
});

p_c([port => [{port => 2202, listen => 6}]], {
    _bind => [{host => '*', port => 2202, proto => 'tcp', listen => 6}],
    sock  => [{
        NS_host => '*',
        NS_port => 2202,
        NS_proto => 'TCP',
        NS_listen => 6,
        NS_family => 0,
    }],
});

###----------------------------------------------------------------###
# unix, unixdgram

if (!eval { require IO::Socket::UNIX }) {
    my $err = $@;
  SKIP: {
      skip "Cannot load IO::Socket::UNIX - skipping UNIX proto tests", 3;
    };
} else {
    p_c([port => 'foo/bar/unix'], {
        _bind => [{host => '*', port => 'foo/bar', proto => 'unix'}],
    });

    p_c([port => '/foo/bar|unix', udp_recv_len => 500], {
        _bind => [{host => '*', port => '/foo/bar', proto => 'unix'}],
        sock  => [{NS_family => 0, NS_host => '*', NS_port => '/foo/bar', NS_proto => 'UNIX', NS_listen => Socket::SOMAXCONN(), NS_unix_type => 'SOCK_STREAM'}],
    });

    p_c([port => '/foo/bar|unixdgram', udp_recv_len => 500], {
        _bind => [{host => '*', port => '/foo/bar', proto => 'unixdgram'}],
        sock  => [{NS_host => '*', NS_port => '/foo/bar', NS_proto => 'UNIXDGRAM', NS_recv_len => 500, NS_recv_flags => 0, NS_unix_type => 'SOCK_DGRAM'}],
    });

    p_c([port => 'foo/bar|sock_dgram|unix'], {
        _bind => [{host => '*', port => 'foo/bar', proto => 'unix', unix_type => 'sock_dgram'}],
    });

    p_c([port => {port => '/foo/bar', proto => 'unix', unix_type => 'sock_stream', listen => 7}], {
        _bind => [{host => '*', port => '/foo/bar', proto => 'unix', unix_type => 'sock_stream', listen => 7}],
        sock  => [{NS_family => 0, NS_host => '*', NS_port => '/foo/bar', NS_proto => 'UNIX', NS_unix_type => 'SOCK_STREAM', NS_listen => 7}],
    });

    p_c([port => {port => '/foo/bar', proto => 'unix', unix_type => 'sock_dgram'}], {
        _bind => [{host => '*', port => '/foo/bar', proto => 'unix', unix_type => 'sock_dgram'}],
    });

    p_c([port => {port => '/foo/bar', proto => 'unixdgram'}], {
        _bind => [{host => '*', port => '/foo/bar', proto => 'unixdgram'}],
    });

}

###----------------------------------------------------------------###
# ssl

if (!eval { require Net::SSLeay; 1 }) {
    my $err = $@;
  SKIP: {
      skip "Cannot load Net::SSLeay - skipping SSLEAY proto tests", 1;
    };
} else {

    p_c([proto => 'ssleay'], {
        _bind => [{host => '*', port => Net::Server::default_port(), proto => 'ssleay'}],
        sock  => [{NS_host => '*', NS_port => 20203, NS_proto => 'SSLEAY', NS_family => 0, NS_listen => eval { Socket::SOMAXCONN() }, SSL_cert_file => FooServer::SSL_cert_file()}],
    });

    %class_m = (); # setting SSL_key_file may dynamically change the package methods
    p_c([port => '2203/ssleay', listen => 4, SSL_key_file => "foo/bar"], {
        _bind => [{host => '*', port => 2203, proto => 'ssleay'}],
        sock  => [{NS_host => '*', NS_port => 2203, NS_proto => 'SSLEAY', NS_family => 0, NS_listen => 4, SSL_key_file => "foo/bar", SSL_cert_file => FooServer::SSL_cert_file()}],
    });

    %class_m = (); # setting SSL_key_file may dynamically change the package methods
    p_c([port => {port => '2203', proto => 'ssleay', listen => 6, SSL_key_file => "foo/bar"}], {
        _bind => [{host => '*', port => 2203, proto => 'ssleay', listen => 6, SSL_key_file => "foo/bar"}],
        sock  => [{NS_host => '*', NS_port => 2203, NS_proto => 'SSLEAY', NS_family => 0, NS_listen => 6, SSL_key_file => "foo/bar", SSL_cert_file => FooServer::SSL_cert_file()}],
    });

}
