package Net::Server::Log::Sys::Syslog;

use strict;
use warnings;
use Sys::Syslog qw(setlogsock openlog syslog);;

our %syslog_map = (0 => 'err', 1 => 'warning', 2 => 'notice', 3 => 'info', 4 => 'debug');

sub initialize {
    my ($class, $server) = @_;
    my $prop = $server->{'server'};

    $server->configure({
        syslog_logsock  => \$prop->{'syslog_logsock'},
        syslog_ident    => \$prop->{'syslog_ident'},
        syslog_logopt   => \$prop->{'syslog_logopt'},
        syslog_facility => \$prop->{'syslog_facility'},
    });

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
        setlogsock($prop->{'syslog_logsock'}) || die "Syslog err [$!]";
    }
    if (! openlog($prop->{'syslog_ident'}, $prop->{'syslog_logopt'}, $prop->{'syslog_facility'})) {
        die "Couldn't open syslog [$!]" if $prop->{'syslog_logopt'} ne 'ndelay';
    }

    return sub {
        my ($level, $msg) = @_;

        if ($level =~ /^\d+$/) {
            return if $level > ($prop->{'log_level'} || 0);
            $level = $syslog_map{$level} || $level;
        }

        syslog($level, '%s', $msg);
    };
}

sub handle_log_error {
    my ($class, $server, $err, $info) = @_;
    return $server->handle_syslog_error($err, $info);
}

1;
