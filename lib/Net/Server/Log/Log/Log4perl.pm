package Net::Server::Log::Log::Log4perl;

use strict;
use warnings;
use Log::Log4perl;

our %log4perl_map = (1 => "error", 2 => "warn", 3 => "info", 4 => "debug");

sub initialize {
    my ($class, $server) = @_;
    my $prop = $server->{'server'};

    $server->configure({
        log4perl_conf   => \$prop->{'log4perl_conf'},
        log4perl_logger => \$prop->{'log4perl_logger'},
        log4perl_poll   => \$prop->{'log4perl_poll'},
    });

    die "Must specify a log4perl_conf file" if ! $prop->{'log4perl_conf'};

    my $poll = defined($prop->{'log4perl_poll'}) ? $prop->{'log4perl_poll'} : "0";
    my $logger = $prop->{'log4perl_logger'} || "Net::Server";

    if ($poll eq "0") {
        Log::Log4perl::init($prop->{'log4perl_conf'});
    } else {
        Log::Log4perl::init_and_watch($prop->{'log4perl_conf'}, $poll);
    }

    my $l4p = Log::Log4perl->get_logger($logger);

    return sub {
        my ($level, $msg, $server_level) = @_;
        return if $level !~ /^\d+$/ || $level > ($server_level || 0);
        $level = $log4perl_map{$level} || "error";
        $l4p->$level($msg);
    };
}

1;
