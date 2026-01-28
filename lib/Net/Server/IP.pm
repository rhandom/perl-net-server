# -*- perl -*-
#
#  Net::Server::IP - IPv4 / IPv6 compatibility module
#
#  Copyright (C) 2025-2026
#
#    Rob Brown <bbb@cpan.org>
#
#  This package may be distributed under the terms of either the
#  GNU General Public License
#    or the
#  Perl Artistic License
#
#  All rights reserved.
#
################################################################

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
    my $family = delete $arg->{'Family'};
    if (defined (my $family2 = delete $arg->{'Domain'}) and !defined $family) { $family = $family2 };
    if (!defined $family and my $addr = $arg->{'LocalHost'} || $arg->{'PeerHost'} || $arg->{'LocalAddr'} || $arg->{'PeerAddr'}) {
        # Use Addr arg to hint which Family to use.
        if ($addr =~ /^(\d+\.\d+\.\d+\.\d+)(|:\w+|\w+\(\d+\))$/) {
            $family = AF_INET; # Surely IPv4
        } elsif ($addr =~ /^\[[a-fA-F\d:]+\](|:\w+|\w+\(\d+\))$/ or $addr =~ /^(?:[a-fA-F\d]*:){2,7}([a-fA-F\d]*|\d+\.\d+\.\d+\.\d+)$/) {
            $family = AF_INET6; # Surely IPv6
        } else {
            $family = AF_UNSPEC; # Some other Host, maybe a DNS word, so can't tell if it's IPv4 or IPv6 yet.
        }
    }
    if ($ISA[0] eq "IO::Socket::INET" and defined $family and $family ne AF_INET) {
        # Look for IPv6-compatible module
        my @try = ($ipv6_package?($ipv6_package):(), @preferred);
        my $pm = sub { (my $f="$_[0].pm") =~ s|::|/|g; $f};
        my ($pkg) = grep { $INC{$pm->($_)} } @try;
        my @err = ();
        for (@try) { last if $pkg; eval{require $pm->($_);$pkg=$_} or push @err, ( $@=~/^(.*)/ && "[$_] $! - $1"); }
        $pkg ? ($ISA[0] = $ipv6_package = $pkg) :
        do { return if $@=join "\n","Preferred ipv6_package (@try) could not be loaded:",@err and $family; $family=undef; };
    }
    if (defined $family) { # Only set the corresponding arg
        $arg->{'Family'} = $family if $self->isa("IO::Socket::IP");
        $arg->{'Domain'} = $family if $self->isa("IO::Socket::INET6");
    }
    return $self->SUPER::configure($arg);
}

1;

__END__

=head1 NAME

Net::Server::IP - IPv4 / IPv6 compatibility module

=head1 SYNOPSIS

    use Net::Server::IP;

    my $sock = Net::Server::IP->new(
        LocalAddr => "[::]",
        LocalPort => 8080,
        Listen => 1,
    ) or die "IPv6 listen error: $@ $!";

    my $sock = Net::Server::IP->new(
        PeerAddr => "[::1]:8080",
    ) or die "IPv6 connect error: $@ $!";

    my $sock = Net::Server::IP->new(
        PeerAddr => "127.0.0.1:8080",
    ) or die "IPv4 connect error: $@ $!";

=head1 DESCRIPTION

In order to support IPv6, Net::Server:IP inherits from either
IO::Socket::IP or IO::Socket::INET6, whichever is available.
This provides a consistent convention regardless of any
differences between these modules. If only IPv4 is required
based on its parameters, then neither module needs to be
installed. Everything will still work fine by only inheriting
from IO::Socket::INET. IO::Socket::IP will take preference,
if available. To override this default behavior:

    $Net::Server::IP::ipv6_package = 'Custom::Mod::Handle';

=head1 INPUTS

=head2 $sock = Net::Server::IP->new( %args )

Creates a new C<Net::Server::IP> handle object.  The arguments
recognized are similar to C<IO::Socket::IP> or C<IO::Socket::INET6>.

Special consideration applies to the following parameters:

=over 8

=item Family => INT (like C<IO::Socket::IP>)

=item Domain => INT (like C<IO::Socket::INET6>)

Address family for the socket. (e.g. C<AF_INET>, C<AF_INET6>)
C<Domain> is synonym for C<Family>. Both args are the same.
C<Family> will take precedence if both are supplied.

If provided, this will be used to determine if IPv6 is required.

=item LocalHost => STRING

=item LocalAddr => STRING

=item PeerHost => STRING

=item PeerAddr => STRING

Hostname with optional Port. If C<Family> is not provided,
then this will be scanned as a hint for which C<Family> to use.

=head1 AUTHOR

Paul Seamons <paul@seamons.com>

Rob Brown <bbb@cpan.org>

=head1 SEE ALSO

L<IO::Socket::IP>,
L<IO::Socket::INET>,
L<IO::Socket::INET6>

=head1 LICENSE

Distributed under the same terms as Net::Server

=cut
