package Net::Server::IP;

use strict;
use warnings;
use Net::Server::Proto qw(AF_INET AF_INET6 AF_UNSPEC);
use IO::Socket::INET ();

our @ISA = qw(IO::Socket::INET); # we may dynamically change this to an IPv6-compatible class based upon our configuration
our $ipv6_package = undef;
our @preferred = qw(IO::Socket::IP IO::Socket::INET6);

sub configure {
    my ($self, $arg) = @_;
    die "configure: no arg" if !$arg or !%$arg;
    if ($ISA[0] eq "IO::Socket::INET" and Net::Server::Proto->requires_ipv6) {
        # Look for IPv6-compatible module
        my @try = ($ipv6_package?($ipv6_package):(), @preferred);
        my $pm = sub { (my $f="$_[0].pm") =~ s|::|/|g; $f};
        my ($pkg) = grep { $INC{$pm->($_)} } @try;
        my @err = ();
        for (@try) { last if $pkg; eval{require $pm->($_);$pkg=$_} or push @err, ( $@=~/^(.*)/ && "[$_] $! - $1"); }
        return if !$pkg and $@ = join "\n","Preferred ipv6_package (@try) could not be loaded:",@err;
        $ISA[0] = $ipv6_package = $pkg;
    }
    return $self->SUPER::configure($arg);
}

1;
