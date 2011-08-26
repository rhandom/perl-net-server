# -*- perl -*-
#
#  Net::Server - Extensible Perl internet server
#
#  $Id$
#
#  Copyright (C) 2001-2011
#
#    Paul Seamons
#    paul@seamons.com
#    http://seamons.com/
#
#    Rob Brown bbb@cpan,org
#
#  This package may be distributed under the terms of either the
#  GNU General Public License
#    or the
#  Perl Artistic License
#
#  All rights reserved.
#
################################################################

package Net::Server;

use strict;
use Socket qw(AF_INET AF_UNIX SOCK_DGRAM SOCK_STREAM);
use IO::Socket ();
use IO::Select ();
use POSIX ();
use Net::Server::Proto ();
use Net::Server::Daemonize qw(check_pid_file create_pid_file safe_fork
                              get_uid get_gid set_uid set_gid);

our $VERSION = '1.01';

sub new {
    my $class = shift || die "Missing class";
    my $args  = @_ == 1 ? shift : {@_};
    return bless {server => {%$args}}, $class;
}

sub get_property { $_[0]->{'server'}->{$_[1]} }
sub set_property { $_[0]->{'server'}->{$_[1]} = $_[2] }

sub run {
    my $self = ref($_[0]) ? shift() : shift->new;  # pass package or object
    $self->_initialize(@_ == 1 ? %{$_[0]} : @_);     # configure all parameters

    $self->post_configure;      # verification of passed parameters
    $self->post_configure_hook; # user customizable hook

    $self->pre_bind;            # finalize ports to be bound
    $self->bind;                # connect to port(s), setup selection handle for multi port
    $self->post_bind_hook;      # user customizable hook
    $self->post_bind;           # allow for chrooting, becoming a different user and group

    $self->pre_loop_hook;       # user customizable hook
    $self->loop;                # repeat accept/process cycle

    $self->server_close;        # close the server and release the port
}

sub run_client_connection {
    my $self = shift;

    $self->post_accept;         # prepare client for processing
    $self->get_client_info;     # determines information about peer and local
    $self->post_accept_hook;    # user customizable hook

    my $ok = $self->allow_deny && $self->allow_deny_hook; # do allow/deny check on client info
    if ($ok) {
        $self->process_request;   # This is where the core functionality of a Net::Server should be.
    } else {
        $self->request_denied_hook;     # user customizable hook
    }

    $self->post_process_request_hook($ok); # user customizable hook
    $self->post_process_request;           # clean up client connection, etc
    $self->post_client_connection_hook;    # one last hook
}

###----------------------------------------------------------------###

sub _initialize {
    my $self = shift;
    my $prop = $self->{'server'} ||= {};

    $self->commandline($self->_get_commandline) if ! eval { $self->commandline }; # save for a HUP
    $self->configure_hook;      # user customizable hook
    $self->configure(@_);       # allow for reading of commandline, program, and configuration file parameters

    my @defaults = %{ $self->default_values || {} }; # allow yet another way to pass defaults
    $self->process_args(\@defaults) if @defaults;
}

sub commandline {
    my $self = shift;
    $self->{'server'}->{'commandline'} = ref($_[0]) ? shift : \@_ if @_;
    return $self->{'server'}->{'commandline'} || die "commandline was not set during initialization";
}

sub _get_commandline {
    my $self = shift;
    if (open my $fh, "<", "/proc/$$/cmdline") { # see if we can find the full command line - unix specific
        my $line = do { local $/ = undef; <$fh> };
        close $fh;
        return [split /\0/, $1] if $line =~ /^(.+)$/; # need to untaint to allow for later hup
    }
    my $script = $0;
    $script = $ENV{'PWD'} .'/'. $script if $script =~ m|^[^/]+/| && $ENV{'PWD'}; # add absolute to relative
    $script =~ /^(.+)$/; # untaint for later use in hup
    return [$1, @ARGV]
}

sub configure_hook {}

sub configure {
    my $self = shift;
    my $prop = $self->{'server'};
    my $template = ($_[0] && ref($_[0])) ? shift : undef;

    $self->process_args(\@ARGV, $template) if @ARGV; # command line
    $self->process_args([@_],   $template);          # passed to run

    if ($prop->{'conf_file'}) {
        $self->process_args($self->_read_conf($prop->{'conf_file'}), $template);
    } else {
        my $def = $self->default_values || {};
        $self->process_args($self->_read_conf($def->{'conf_file'}), $template) if $def->{'conf_file'};
    }
}

sub default_values { {} }

sub post_configure {
    my $self = shift;
    my $prop = $self->{'server'};

    $prop->{'log_level'} = 2 if ! defined($prop->{'log_level'}) || $prop->{'log_level'} !~ /^\d+$/;
    $prop->{'log_level'} = 4 if $prop->{'log_level'} > 4;

    if (! defined($prop->{'log_file'})) {
        $prop->{'log_file'} = ''; # log to STDERR

    } elsif ($prop->{'log_file'} eq 'Sys::Syslog') {
        $self->configure({
            syslog_logsock  => \$prop->{'syslog_logsock'},
            syslog_ident    => \$prop->{'syslog_ident'},
            syslog_logopt   => \$prop->{'syslog_logopt'},
            syslog_facility => \$prop->{'syslog_facility'},
        });
        $self->open_syslog; # log to syslog

    } elsif ($prop->{'log_file'}) {
        die "Unsecure filename \"$prop->{'log_file'}\"" if $prop->{'log_file'} !~ m|^([\:\w\.\-/\\]+)$|;
        $prop->{'log_file'} = $1; # open a logging file
        open(_SERVER_LOG, ">>", $prop->{'log_file'})
            || die "Couldn't open log file \"$prop->{'log_file'}\" [$!].";
        _SERVER_LOG->autoflush(1);
        $prop->{'chown_log_file'} = 1;
    }

    if ($prop->{'pid_file'}) { # see if a daemon is already running
        if (! eval{ check_pid_file($prop->{'pid_file'}) }) {
            warn $@ if !$ENV{'BOUND_SOCKETS'};
            $self->fatal(my $e = $@);
        }
    }

    if (! $prop->{'_is_inet'}) { # completetly daemonize by closing STDIN, STDOUT (should be done before fork)
        if ($prop->{'setsid'} || length($prop->{'log_file'})) {
            open(STDIN,  '<', '/dev/null') || die "Cannot read /dev/null  [$!]";
            open(STDOUT, '>', '/dev/null') || die "Cannot write /dev/null [$!]";
        }
    }

    if (!$ENV{'BOUND_SOCKETS'}) { # don't need to redo this if hup'ing
        if ($prop->{'setsid'} || $prop->{'background'}) {
            my $pid = eval { safe_fork() };
            $self->fatal(my $e = $@) if ! defined $pid;
            exit(0) if $pid;
            $self->log(2, "Process Backgrounded");
        }

        POSIX::setsid() if $prop->{'setsid'}; # completely remove myself from parent process
    }

    if (length($prop->{'log_file'}) && $prop->{'log_file'} ne 'Sys::Syslog') { # completely daemonize by closing STDERR (should be done after fork)
        open STDERR, '>&_SERVER_LOG' || die "Cannot open STDERR to _SERVER_LOG [$!]";
    } elsif ($prop->{'setsid'}) {
        open STDERR, '>&STDOUT' || die "Cannot open STDERR to STDOUT [$!]";
    }

    # allow for a pid file (must be done after backgrounding and chrooting)
    # Remove of this pid may fail after a chroot to another location... however it doesn't interfere either.
    if ($prop->{'pid_file'}) {
        if (eval { create_pid_file($prop->{'pid_file'}) }) {
            $prop->{'pid_file_unlink'} = 1;
        } else {
            $self->fatal(my $e = $@);
        }
    }

    # make sure that allow and deny look like array refs
    $prop->{$_} = [] for grep {! ref $prop->{$_}} qw(allow deny cidr_allow cidr_deny);
}

sub post_configure_hook {}

sub pre_bind { # make sure we have good port parameters
    my $self = shift;
    my $prop = $self->{'server'};

    my $super = do { no strict 'refs'; ${ref($self)."::ISA"}[0] };
    $super = "$super -> MultiType -> $Net::Server::MultiType::ISA[0]" if $self->isa('Net::Server::MultiType');
    $super = (! $super || ref($self) eq $super) ? '' : " (type $super)";
    $self->log(2, $self->log_time ." ".ref($self)."$super starting! pid($$)");

    $prop->{'sock'} = [grep {$_} map { $self->proto_object($_) } @{ $self->prepared_ports }];
    $self->fatal("No valid socket parameters found") if ! @{ $prop->{'sock'} };

    if (!$prop->{'listen'} || $prop->{'listen'} !~ /^\d+$/) {
        my $max = Socket::SOMAXCONN();
        $max = 128 if $max < 10; # some invalid Solaris constants ?
        $prop->{'listen'} = $max;
        $self->log(2, "Using default listen value of $max");
    }
}

sub prepared_ports {
    my $self = shift;
    my $prop = $self->{'server'};
    my $bind = $prop->{'_bind'} = [];

    my ($ports, $hosts, $protos) = @$prop{qw(port host proto)};
    $ports ||= $prop->{'ports'};
    if (!defined($ports) || (ref($ports) && !@$ports)) {
        $ports = $self->default_port;
        if (!defined($ports) || (ref($ports) && !@$ports)) {
            $ports = default_port();
            $self->log(2, "Port Not Defined.  Defaulting to '$ports'");
        }
    }

    my %bound;
    for my $_port (ref($ports) ? @$ports : $ports) {
        my $_host  = ref($hosts)  ? $hosts->[ @$bind >= @$hosts  ? -1 : $#$bind + 1] : $hosts; # if ports are greater than hosts - augment with the last host
        my $_proto = ref($protos) ? $protos->[@$bind >= @$protos ? -1 : $#$bind + 1] : $protos;
        my $info   = $self->proto_info($_port, $_host, $_proto);
        my ($port, $host, $proto) = @$info{qw(port host proto)}; # use cleaned values
        if ($port ne "0" && $bound{"$host/$port/$proto"}++) {
            $self->log(2, "Duplicate configuration (".(uc $proto)." on [$host]:$port - skipping");
            next;
        }
        push @$bind, $info;
    }

    return $bind;
}

sub proto_info {
    my ($self, $port, $host, $proto) = @_;
    return Net::Server::Proto->parse_info($port, $host, $proto, $self);
}

sub proto_object {
    my ($self, $info) = @_;
    return Net::Server::Proto->object($info, $self);
}

sub bind { # bind to the port (This should serve all but INET)
    my $self = shift;
    my $prop = $self->{'server'};

    if (exists $ENV{'BOUND_SOCKETS'}) {
        $self->restart_open_hook;
        $self->log(2, "Binding open file descriptors");
        foreach my $info (split /\n/, $ENV{'BOUND_SOCKETS'}) {
            my ($fd, $hup_string) = split /\|/, $info, 2;
            $fd = ($fd =~ /^(\d+)$/) ? $1 : $self->fatal("Bad file descriptor");
            foreach my $sock (@{ $prop->{'sock'} }) {
                if ($hup_string eq $sock->hup_string) {
                    $sock->log_connect($self);
                    $sock->reconnect($fd, $self);
                    last;
                }
            }
        }
        delete $ENV{'BOUND_SOCKETS'};
        $self->{'hup_waitpid'} = 1;

    } else { # connect to fresh ports
        foreach my $sock (@{ $prop->{'sock'} }) {
            $sock->log_connect($self);
            $sock->connect($self);
        }
    }

    if (@{ $prop->{'sock'} } > 1 || $prop->{'multi_port'}) {
        $prop->{'multi_port'} = 1;
        $prop->{'select'} = IO::Select->new; # if more than one socket we'll need to select on it
        $prop->{'select'}->add($_) for @{ $prop->{'sock'} };
    } else {
        $prop->{'multi_port'} = undef;
        $prop->{'select'}     = undef;
    }
}

sub post_bind_hook {}


sub post_bind { # secure the process and background it
    my $self = shift;
    my $prop = $self->{'server'};

    if (! defined $prop->{'group'}) {
        $self->log(1, "Group Not Defined.  Defaulting to EGID '$)'");
        $prop->{'group'} = $);
    } elsif ($prop->{'group'} =~ /^([\w-]+(?: [\w-]+)*)$/) {
        $prop->{'group'} = eval { get_gid($1) };
        $self->fatal(my $e = $@) if $@;
    } else {
        $self->fatal("Invalid group \"$prop->{'group'}\"");
    }

    if (! defined $prop->{'user'}) {
        $self->log(1, "User Not Defined.  Defaulting to EUID '$>'");
        $prop->{'user'} = $>;
    } elsif ($prop->{'user'} =~ /^([\w-]+)$/) {
        $prop->{'user'} = eval { get_uid($1) };
        $self->fatal(my $e = $@) if $@;
    } else {
        $self->fatal("Invalid user \"$prop->{'user'}\"");
    }

    # chown any files or sockets that we need to
    if ($prop->{'group'} ne $) || $prop->{'user'} ne $>) {
        my @chown_files;
        push @chown_files, map {$_->NS_unix_path} grep {$_->NS_proto eq 'UNIX'} @{ $prop->{'sock'} };
        push @chown_files, $prop->{'pid_file'}  if $prop->{'pid_file_unlink'};
        push @chown_files, $prop->{'lock_file'} if $prop->{'lock_file_unlink'};
        push @chown_files, $prop->{'log_file'}  if delete $prop->{'chown_log_file'};
        my $uid = $prop->{'user'};
        my $gid = (split /\ /, $prop->{'group'})[0];
        foreach my $file (@chown_files){
            chown($uid, $gid, $file) || $self->fatal("Couldn't chown \"$file\" [$!]");
        }
    }

    if ($prop->{'chroot'}) {
        $self->fatal("Specified chroot \"$prop->{'chroot'}\" doesn't exist.") if ! -d $prop->{'chroot'};
        $self->log(2, "Chrooting to $prop->{'chroot'}");
        chroot($prop->{'chroot'}) || $self->fatal("Couldn't chroot to \"$prop->{'chroot'}\": $!");
    }

    # drop privileges
    eval {
        if ($prop->{'group'} ne $)) {
            $self->log(2, "Setting gid to \"$prop->{'group'}\"");
            set_gid($prop->{'group'} );
        }
        if ($prop->{'user'} ne $>) {
            $self->log(2, "Setting uid to \"$prop->{'user'}\"");
            set_uid($prop->{'user'});
        }
    };
    if ($@) {
        if ($> == 0) {
            $self->fatal(my $e = $@);
        } elsif ($< == 0) {
            $self->log(2, "NOTICE: Effective UID changed, but Real UID is 0: $@");
        } else {
            $self->log(2, my $e = $@);
        }
    }

    $prop->{'requests'} = 0; # record number of request

    $SIG{'INT'}  = $SIG{'TERM'} = $SIG{'QUIT'} = sub { $self->server_close; };
    $SIG{'PIPE'} = 'IGNORE'; # most cases, a closed pipe will take care of itself
    $SIG{'CHLD'} = \&sig_chld; # catch children (mainly for Fork and PreFork but works for any chld)
    $SIG{'HUP'}  = sub { $self->sig_hup };
}

sub sig_chld {
    1 while waitpid(-1, POSIX::WNOHANG()) > 0;
    $SIG{'CHLD'} = \&sig_chld;
}

sub pre_loop_hook {}

sub loop {
    my $self = shift;
    while ($self->accept) {
        $self->run_client_connection;
        last if $self->done;
    }
}

sub accept {
    my $self = shift;
    my $prop = $self->{'server'};

    my $sock = undef;
    my $retries = 30;
    while ($retries--) {
        if ($prop->{'multi_port'}) { # with more than one port, use select to get the next one
            return 0 if $prop->{'_HUP'};
            $sock = $self->accept_multi_port || next; # keep trying for the rest of retries
            return 0 if $prop->{'_HUP'};
            if ($self->can_read_hook($sock)) {
                $retries++;
                next;
            }
        } else {
            $sock = $prop->{'sock'}->[0]; # single port is bound - just accept
        }
        $self->fatal("Received a bad sock!") if ! defined $sock;

        if (SOCK_DGRAM == $sock->getsockopt(Socket::SOL_SOCKET(), Socket::SO_TYPE())) { # receive a udp packet
            $prop->{'client'}   = $sock;
            $prop->{'udp_true'} = 1;
            $prop->{'udp_peer'} = $sock->recv($prop->{'udp_data'}, $sock->NS_recv_len, $sock->NS_recv_flags);

        } else { # blocking accept per proto
            delete $prop->{'udp_true'};
            $prop->{'client'} = $sock->accept();
        }

        return 0 if $prop->{'_HUP'};
        return 1 if $prop->{'client'};

        $self->log(2,"Accept failed with $retries tries left: $!");
        sleep(1);
    }

    $self->log(1,"Ran out of accept retries!");
    return undef;
}


sub accept_multi_port {
    my @waiting = shift->{'server'}->{'select'}->can_read();
    return undef if ! @waiting;
    return $waiting[rand @waiting];
}

sub can_read_hook {}

sub post_accept {
    my $self = shift;
    my $prop = $self->{'server'};
    $prop->{'requests'}++;
    return if $prop->{'udp_true'}; # no need to do STDIN/STDOUT in UDP

    if (my $client = $prop->{'client'}) {
        if (! $prop->{'no_client_stdout'}) {
            close STDIN; # duplicate some handles and flush them
            close STDOUT;
            if ($prop->{'tie_client_stdout'} || ($client->can('tie_stdout') && $client->tie_stdout)) {
                open STDIN,  '<', '/dev/null' or die "Couldn't open STDIN to the client socket: $!";
                open STDOUT, '>', '/dev/null' or die "Couldn't open STDOUT to the client socket: $!";
                tie *STDOUT, 'Net::Server::TiedHandle', $client, $prop->{'tied_stdout_callback'} or die "Couldn't tie STDOUT: $!";
                tie *STDIN,  'Net::Server::TiedHandle', $client, $prop->{'tied_stdin_callback'}  or die "Couldn't tie STDIN: $!";
            } elsif (defined(my $fileno = fileno $prop->{'client'})) {
                open STDIN,  '<&', $fileno or die "Couldn't open STDIN to the client socket: $!";
                open STDOUT, '>&', $fileno or die "Couldn't open STDOUT to the client socket: $!";
            } else {
                *STDIN  = \*{ $prop->{'client'} };
                *STDOUT = \*{ $prop->{'client'} };
            }
            STDIN->autoflush(1);
            STDOUT->autoflush(1);
            select STDOUT;
        }
    } else {
        $self->log(1,"Client socket information could not be determined!");
    }
}

sub get_client_info {
    my $self = shift;
    my $prop = $self->{'server'};

    my $sock = $prop->{'client'};
    if ($sock->can('NS_proto') && $sock->NS_proto eq 'UNIX') {
        $self->log(3, $self->log_time." CONNECT UNIX Socket: \"".$sock->NS_unix_path."\"") if $prop->{'log_level'} && 3 <= $prop->{'log_level'};
        return;
    }

    if (my $sockname = $sock->sockname) {
        $prop->{'sockaddr'} = $sock->sockhost;
        $prop->{'sockport'} = $sock->sockport;
    } else {
        @{ $prop }{qw(sockaddr sockhost sockport)} = ($ENV{'REMOTE_HOST'} || '0.0.0.0', 'inet.test', 0); # commandline
    }

    my $addr;
    if ($prop->{'udp_true'}) {
        if ($sock->sockdomain == AF_INET) {
            ($prop->{'peerport'}, $addr) = Socket::sockaddr_in($prop->{'udp_peer'});
            $prop->{'peeraddr'} = Socket::inet_ntoa($addr);
        } else {
            ($prop->{'peerport'}, $addr) = Socket6::sockaddr_in6($prop->{'udp_peer'});
            $prop->{'peeraddr'} = Socket6->can('inet_ntop')
                                ? Socket6::inet_ntop($sock->sockdomain, $addr)
                                : Socket::inet_ntoa($addr);
        }
    } elsif ($prop->{'peername'} = $sock->peername) {
        $addr               = $sock->peeraddr;
        $prop->{'peeraddr'} = $sock->peerhost;
        $prop->{'peerport'} = $sock->peerport;
    } else {
        @{ $prop }{qw(peeraddr peerhost peerport)} = ('0.0.0.0', 'inet.test', 0); # commandline
    }

    if ($addr && defined $prop->{'reverse_lookups'}) {
        if ($INC{'Socket6.pm'} && Socket6->can('getnameinfo')) {
            my @res = Socket6::getnameinfo($addr, 0);
            $prop->{'peerhost'} = $res[0] if @res > 1;
        }else{
            $prop->{'peerhost'} = gethostbyaddr($addr, AF_INET);
        }
    }

    $self->log(3, $self->log_time
               ." CONNECT ".($prop->{'udp_true'}?'UDP':'TCP')." Peer: \"$prop->{'peeraddr'}:$prop->{'peerport'}\""
               ." Local: \"[$prop->{'sockaddr'}]:$prop->{'sockport'}\"") if $prop->{'log_level'} && 3 <= $prop->{'log_level'};
}

sub post_accept_hook {}

sub allow_deny {
    my $self = shift;
    my $prop = $self->{'server'};
    my $sock = $prop->{'client'};

    # unix sockets are immune to this check
    return 1 if $sock && UNIVERSAL::can($sock,'NS_proto') && $sock->NS_proto eq 'UNIX';

    # if no allow or deny parameters are set, allow all
    return 1 if ! @{ $prop->{'allow'} }
             && ! @{ $prop->{'deny'} }
             && ! @{ $prop->{'cidr_allow'} }
             && ! @{ $prop->{'cidr_deny'} };

    # if the addr or host matches a deny, reject it immediately
    foreach (@{ $prop->{'deny'} }) {
        return 0 if $prop->{'peerhost'} =~ /^$_$/ && defined $prop->{'reverse_lookups'};
        return 0 if $prop->{'peeraddr'} =~ /^$_$/;
    }
    if (@{ $prop->{'cidr_deny'} }) {
        require Net::CIDR;
        return 0 if Net::CIDR::cidrlookup($prop->{'peeraddr'}, @{ $prop->{'cidr_deny'} });
    }

    # if the addr or host isn't blocked yet, allow it if it is allowed
    foreach (@{ $prop->{'allow'} }) {
        return 1 if $prop->{'peerhost'} =~ /^$_$/ && defined $prop->{'reverse_lookups'};
        return 1 if $prop->{'peeraddr'} =~ /^$_$/;
    }
    if (@{ $prop->{'cidr_allow'} }) {
        require Net::CIDR;
        return 1 if Net::CIDR::cidrlookup($prop->{'peeraddr'}, @{ $prop->{'cidr_allow'} });
    }

    return 0;
}

sub allow_deny_hook { 1 } # false to deny request

sub request_denied_hook {}

sub process_request { # sample echo server - override for full functionality
    my $self = shift;
    my $prop = $self->{'server'};

    if ($prop->{'udp_true'}) { # udp echo server
        if ($prop->{'udp_data'} =~ /dump/) {
            require Data::Dumper;
            return $prop->{'client'}->send(Data::Dumper::Dumper($self), 0);
        }
        return $prop->{'client'}->send("You said \"$prop->{'udp_data'}\"", 0);
    }

    print "Welcome to \"".ref($self)."\" ($$)\r\n";
    my $previous_alarm = alarm(30);
    eval {
        local $SIG{'ALRM'} = sub { die "Timed Out!\n" };
        while (<STDIN>) {
            s/\r?\n$//;
            print ref($self),":$$: You said \"$_\"\r\n";
            $self->log(5, $_); # very verbose log
            if (/get\s+(\w+)/) { print "$1: $self->{'server'}->{$1}\r\n" }
            elsif (/dump/) { require Data::Dumper; print Data::Dumper::Dumper($self) }
            elsif (/quit/) { last }
            elsif (/exit/) { $self->server_close }
            alarm(30); # another 30
        }
        alarm($previous_alarm);
    };
    print "Timed Out.\r\n" if $@ eq "Timed Out!\n";
}

sub post_process_request_hook {}

sub post_client_connection_hook {}

sub post_process_request {
    my $self = shift;
    my $prop = $self->{'server'};
    return if $prop->{'udp_true'};

    if (! $prop->{'no_client_stdout'}) {
        untie *STDOUT if tied *STDOUT;
        untie *STDIN  if tied *STDIN;
        open(STDIN,  '<', '/dev/null') || die "Cannot read /dev/null  [$!]";
        open(STDOUT, '>', '/dev/null') || die "Cannot write /dev/null [$!]";
    }
    $prop->{'client'}->close;
}

sub done {
    my $self = shift;
    $self->{'server'}->{'done'} = shift if @_;
    return $self->{'server'}->{'done'};
}


sub run_dequeue { # fork off a child process to handle dequeuing
    my $self = shift;
    my $pid  = fork;
    $self->fatal("Bad fork [$!]") if ! defined $pid;
    if (!$pid) { # child
        $self->dequeue();
        exit;
    }

    $self->{'server'}->{'children'}->{$pid}->{'status'} = 'dequeue';
}

sub default_port { 20203 }

sub dequeue {}

sub pre_server_close_hook {}

sub server_close {
    my ($self, $exit_val) = @_;
    my $prop = $self->{'server'};

    $SIG{'INT'} = 'DEFAULT';

    ### if this is a child process, signal the parent and close
    ### normally the child shouldn't, but if they do...
    ### otherwise the parent continues with the shutdown
    ### this is safe for non standard forked child processes
    ### as they will not have server_close as a handler
    if (defined($prop->{'ppid'})
        && $prop->{'ppid'} != $$
        && ! defined($prop->{'no_close_by_child'})) {
        $self->close_parent;
        exit;
    }

    $self->pre_server_close_hook;

    $self->log(2,$self->log_time . " Server closing!");

    if (defined($prop->{'_HUP'}) && $prop->{'leave_children_open_on_hup'}) {
        $self->hup_children;

    } else {
        use CGI::Ex::Dump qw(debug);
        $self->close_children() if $prop->{'children'};
        $self->post_child_cleanup_hook;
    }

    if (defined($prop->{'lock_file'})
        && -e $prop->{'lock_file'}
        && defined($prop->{'lock_file_unlink'})) {
        unlink($prop->{'lock_file'}) || $self->log(1, "Couldn't unlink \"$prop->{'lock_file'}\" [$!]");
    }
    if (defined($prop->{'pid_file'})
        && -e $prop->{'pid_file'}
        && !defined($prop->{'_HUP'})
        && defined($prop->{'pid_file_unlink'})) {
        unlink($prop->{'pid_file'}) || $self->log(1, "Couldn't unlink \"$prop->{'pid_file'}\" [$!]");
    }

    if (defined $prop->{'_HUP'}) {
        $self->restart_close_hook();
        $self->hup_server; # execs at the end
    }

    $self->shutdown_sockets;
    return $self if $prop->{'no_exit_on_close'};
    $self->server_exit($exit_val);
}

sub server_exit {
    my ($self, $exit_val) = @_;
    exit($exit_val || 0);
}

sub shutdown_sockets {
    my $self = shift;
    my $prop = $self->{'server'};

    foreach my $sock (@{ $prop->{'sock'} }) { # unlink remaining socket files (if any)
        $sock->shutdown(2);
        unlink $sock->NS_unix_path if $sock->NS_proto eq 'UNIX';
    }

    $prop->{'sock'} = []; # delete the sock objects
    return 1;
}

### Allow children to send INT signal to parent (or use another method)
### This method is only used by forking servers
sub close_parent {
    my $self = shift;
    my $prop = $self->{'server'};
    die "Missing parent pid (ppid)" if ! $prop->{'ppid'};
    kill 2, $prop->{'ppid'};
}

### SIG INT the children
### This method is only used by forking servers (ie Fork, PreFork)
sub close_children {
    my $self = shift;
    my $prop = $self->{'server'};

    return unless $prop->{'children'} && scalar keys %{ $prop->{'children'} };

    foreach my $pid (keys %{ $prop->{'children'} }) {
        if (kill(15, $pid) || ! kill(0, $pid)) { # if it is killable, kill it
            $self->delete_child($pid);
        }
    }

    1 while waitpid(-1, POSIX::WNOHANG()) > 0;
}


sub is_prefork { 0 }

sub hup_children {
    my $self = shift;
    my $prop = $self->{'server'};

    return unless defined $prop->{'children'} && scalar keys %{ $prop->{'children'} };
    return if ! $self->is_prefork;
    $self->log(2, "Sending children hup signal during HUP on prefork server");

    kill(1, $_) for keys %{ $prop->{'children'} };
}

sub post_child_cleanup_hook {}

### handle sig hup
### this will prepare the server for a restart via exec
sub sig_hup {
    my $self = shift;
    my $prop = $self->{'server'};

    my $i  = 0;
    my @fd;
    $prop->{'_HUP'} = [];
    foreach my $sock (@{ $prop->{'sock'} }) {
        my $fd = POSIX::dup($sock->fileno) || $self->fatal("Cannot duplicate the socket [$!]");

        # hold on to the socket copy until exec;
        # just temporary: any socket domain will do,
        # forked process will decide to use IO::Socket::INET6 if necessary
        $prop->{'_HUP'}->[$i] = IO::Socket::INET->new;
        $prop->{'_HUP'}->[$i]->fdopen($fd, 'w') || $self->fatal("Cannot open to file descriptor [$!]");

        # turn off the FD_CLOEXEC bit to allow reuse on exec
        require Fcntl;
        $prop->{'_HUP'}->[$i]->fcntl(Fcntl::F_SETFD(), my $flags = "");

        push @fd, $fd .'|'. $sock->hup_string; # save host|port|proto|family, and file descriptor

        $sock->close();
        $i++;
    }
    delete $prop->{'select'}; # remove any blocking obstacle
    $ENV{'BOUND_SOCKETS'} = join "\n", @fd;

    if ($prop->{'leave_children_open_on_hup'} && scalar keys %{ $prop->{'children'} }) {
        $ENV{'HUP_CHILDREN'} = join "\n", map {"$_\t$prop->{'children'}->{$_}->{'status'}"} sort keys %{ $prop->{'children'} };
    }
}


sub hup_server {
    my $self = shift;
    $self->log(0, $self->log_time()." HUP'ing server");
    delete @ENV{$self->hup_delete_env_keys};
    exec @{ $self->commandline };
}

sub hup_delete_env_keys { return qw(PATH) }

sub restart_open_hook {} # this hook occurs if a server has been HUP'ed it occurs just before opening to the fileno's

sub restart_close_hook {} # this hook occurs if a server has been HUP'ed it occurs just before exec'ing the server

###----------------------------------------------------------###

sub fatal {
    my ($self, $error) = @_;
    my ($package, $file, $line) = caller;
    $self->fatal_hook($error, $package, $file, $line);
    $self->log(0, $self->log_time ." $error\n  at line $line in file $file");
    $self->server_close(1);
}

sub fatal_hook {}

###----------------------------------------------------------###

sub open_syslog {
    my $self = shift;
    my $prop = $self->{'server'};

    require Sys::Syslog;
    if (ref($prop->{'syslog_logsock'}) eq 'ARRAY') {
        # do nothing - assume they have what they want
    } else {
        if (! defined $prop->{'syslog_logsock'}) {
            $prop->{'syslog_logsock'} = ($Sys::Syslog::VERSION < 0.15) ? 'unix' : '';
        }
        if ($prop->{'syslog_logsock'} =~ /^(|native|tcp|udp|unix|inet|stream|console)$/) {
            $prop->{'syslog_logsock'} = $1;
        } else {
            $prop->{'syslog_logsock'} = ($Sys::Syslog::VERSION < 0.15) ? 'unix' : '';
        }
    }

    my $ident = defined($prop->{'syslog_ident'}) ? $prop->{'syslog_ident'} : 'net_server';
    $prop->{'syslog_ident'} = ($ident =~ /^([\ -~]+)$/) ? $1 : 'net_server';

    my $opt = defined($prop->{'syslog_logopt'}) ? $prop->{'syslog_logopt'} : $Sys::Syslog::VERSION ge '0.15' ? 'pid,nofatal' : 'pid';
    $prop->{'syslog_logopt'} = ($opt =~ /^( (?: (?:cons|ndelay|nowait|pid|nofatal) (?:$|[,|]) )* )/x) ? $1 : 'pid';

    my $fac = defined($prop->{'syslog_facility'}) ? $prop->{'syslog_facility'} : 'daemon';
    $prop->{'syslog_facility'} = ($fac =~ /^((\w+)($|\|))*/) ? $1 : 'daemon';

    if ($prop->{'syslog_logsock'}) {
        Sys::Syslog::setlogsock($prop->{'syslog_logsock'}) || die "Syslog err [$!]";
    }
    if (! Sys::Syslog::openlog($prop->{'syslog_ident'}, $prop->{'syslog_logopt'}, $prop->{'syslog_facility'})) {
        die "Couldn't open syslog [$!]" if $prop->{'syslog_logopt'} ne 'ndelay';
    }
}

$Net::Server::syslog_map = {0 => 'err', 1 => 'warning', 2 => 'notice', 3 => 'info', 4 => 'debug'};

sub log {
    my ($self, $level, $msg, @therest) = @_;
    my $prop = $self->{'server'};
    return if ! $prop->{'log_level'};
    $msg = sprintf($msg, @therest) if @therest; # if multiple arguments are passed, assume that the first is a format string

    # log only to syslog if setup to do syslog
    if (defined($prop->{'log_file'}) && $prop->{'log_file'} eq 'Sys::Syslog') {
        if ($level =~ /^\d+$/) {
            return if $level > $prop->{'log_level'};
            $level = $Net::Server::syslog_map->{$level} || $level;
        }

        if (! eval { Sys::Syslog::syslog($level, '%s', $msg); 1 }) {
            my $err = $@;
            $self->handle_syslog_error($err, [$level, $msg]);
        }
        return;
    }

    return if $level !~ /^\d+$/ || $level > $prop->{'log_level'};
    $self->write_to_log_hook($level, $msg);
}


sub handle_syslog_error { my ($self, $error) = @_; die $error }

sub write_to_log_hook {
    my ($self, $level, $msg) = @_;
    my $prop = $self->{'server'};
    chomp $msg;
    $msg =~ s/([^\n\ -\~])/sprintf("%%%02X",ord($1))/eg;

    if ($prop->{'log_file'}) {
        print _SERVER_LOG $msg, "\n";
    } elsif ($prop->{'setsid'}) {
        # do nothing ?
    } else {
        my $old = select STDERR;
        print $msg. "\n";
        select $old;
    }
}


sub log_time {
    my ($sec,$min,$hour,$day,$mon,$year) = localtime;
    return sprintf "%04d/%02d/%02d-%02d:%02d:%02d", $year + 1900, $mon + 1, $day, $hour, $min, $sec;
}

###----------------------------------------------------------###

sub options {
    my $self = shift;
    my $ref  = shift || {};
    my $prop = $self->{'server'};

    foreach (qw(port host proto allow deny cidr_allow cidr_deny)) {
        if (! defined $prop->{$_}) {
            $prop->{$_} = [];
        } elsif (! ref $prop->{$_}) {
            $prop->{$_} = [$prop->{$_}]; # nicely turn us into an arrayref if we aren't one already
        }
        $ref->{$_} = $prop->{$_};
    }

    foreach (qw(conf_file
                user group chroot log_level
                log_file pid_file background setsid
                listen reverse_lookups
                no_close_by_child
                no_client_stdout tie_client_stdout tied_stdout_callback tied_stdin_callback
                leave_children_open_on_hup
                )) {
        $ref->{$_} = \$prop->{$_};
    }
    return $ref;
}


### routine for parsing commandline, module, and conf file
### method has the benefit of leaving unused arguments in @ARGV
sub process_args {
    my ($self, $args, $template) = @_;
    $self->options($template = {}) if ! $template || ! ref $template;

    # we want subsequent calls to not overwrite or add to previously set values so that command line arguments win
    my %previously_set;
    foreach (my $i = 0; $i < @$args; $i++) {
        if ($args->[$i] =~ /^(?:--)?(\w+)(?:[=\ ](\S+))?$/
            && exists $template->{$1}) {
            my ($key, $val) = ($1, $2);
            splice @$args, $i, 1;
            if (! defined $val) {
                if ($i > $#$args
                    || ($args->[$i] && $args->[$i] =~ /^--\w+/)) {
                    $val = 1; # allow for options such as --setsid
                } else {
                    $val = splice @$args, $i, 1;
                    $val = $val->[0] if ref($val) eq 'ARRAY' && @$val == 1 && ref($template->{$key}) ne 'ARRAY';
                }
            }
            $i--;
            $val =~ s/%([A-F0-9])/chr(hex $1)/eig if ! ref $val;

            if (ref $template->{$key} eq 'ARRAY') {
                if (! defined $previously_set{$key}) {
                    $previously_set{$key} = scalar @{ $template->{$key} };
                }
                next if $previously_set{$key};
                push @{ $template->{$key} }, ref($val) eq 'ARRAY' ? @$val : $val;
            } else {
                if (! defined $previously_set{$key}) {
                    $previously_set{$key} = defined(${ $template->{$key} }) ? 1 : 0;
                }
                next if $previously_set{$key};
                die "Found multiple values on the configuration item \"$key\" which expects only one value" if ref($val) eq 'ARRAY';
                ${ $template->{$key} } = $val;
            }
        }
    }
}

sub _read_conf {
    my ($self, $file) = @_;
    my @args;
    $file = ($file =~ m|^([\w\.\-\/\\\:]+)$|) ? $1 : $self->fatal("Unsecure filename \"$file\"");
    open my $fh, '<', $file or do {
        $self->fatal("Couldn't open conf \"$file\" [$!]") if $ENV{'BOUND_SOCKETS'};
        warn "Couldn't open conf \"$file\" [$!]\n";
    };
    while (defined(my $line = <$fh>)) {
        push @args, $1, $2 if $line =~ m/^\s* ((?:--)?\w+) (?:\s*[=:]\s*|\s+) (\S+)/x;
    }
    close $fh;
    return \@args;
}

###----------------------------------------------------------------###

sub other_child_died_hook {}

sub delete_child {
    my ($self, $pid) = @_;
    my $prop = $self->{'server'};

    return $self->other_child_died_hook($pid) if ! exists $prop->{'children'}->{$pid};

    ### prefork server check to clear child communication
    if ($prop->{'child_communication'}) {
        if ($prop->{'children'}->{$pid}->{'sock'}) {
            $prop->{'child_select'}->remove($prop->{'children'}->{$pid}->{'sock'});
            $prop->{'children'}->{$pid}->{'sock'}->close;
        }
    }

    delete $prop->{'children'}->{$pid};
}

# send signal to all children - used by forking servers
sub sig_pass {
    my ($self, $sig) = @_;
    foreach my $chld (keys %{ $self->{'server'}->{'children'} }) {
        $self->log(4, "signaling $chld with $sig" );
        kill($sig, $chld) || $self->log(1, "child $chld not signaled with $sig");
    }
}

# register sigs to allow passthrough to children
sub register_sig_pass {
    my $self = shift;
    my $ref  = $self->{'server'}->{'sig_passthrough'} || [];
    $ref = [$ref] if ! ref $ref;
    $self->fatal('invalid sig_passthrough') if ref $ref ne 'ARRAY';
    return if ! @$ref;
    $self->log(4, "sig_passthrough option found");
    foreach my $sig (@$ref) {
        my $code = ref($SIG{$sig}) eq 'CODE' ? $SIG{$sig} : undef;
        Net::Server::SIG::register_sig($sig => sub { $self->sig_pass($sig); $code->($sig) if $code; }); # should already be loaded
        $self->log(4, "Installed passthrough for $sig");
    }
}

###----------------------------------------------------------------###

package Net::Server::TiedHandle;
sub TIEHANDLE { my $pkg = shift; return bless [@_], $pkg }
sub READLINE { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'getline',  @_) : $s->[0]->getline }
sub SAY      { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'say',      @_) : $s->[0]->say(@_) }
sub PRINT    { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'print',    @_) : $s->[0]->print(@_) }
sub PRINTF   { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'printf',   @_) : $s->[0]->printf(@_) }
sub READ     { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'read',     @_) : $s->[0]->read(@_) }
sub WRITE    { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'write',    @_) : $s->[0]->write(@_) }
sub SYSREAD  { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'sysread',  @_) : $s->[0]->sysread(@_) }
sub SYSWRITE { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'syswrite', @_) : $s->[0]->syswrite(@_) }
sub SEEK     { my $s = shift; $s->[1] ? $s->[1]->($s->[0], 'seek',     @_) : $s->[0]->seek(@_) }

1;

### The documentation is in Net/Server.pod
