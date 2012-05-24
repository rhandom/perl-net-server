# -*- perl -*-
#
#  Net::Server::PSGI - Extensible Perl HTTP PSGI base server
#
#  $Id$
#
#  Copyright (C) 2010-2012
#
#    Paul Seamons
#    paul@seamons.com
#    http://seamons.com/
#
#  This package may be distributed under the terms of either the
#  GNU General Public License
#    or the
#  Perl Artistic License
#
################################################################

package Net::Server::PSGI;

use strict;
use base qw(Net::Server::HTTP);

sub psgi_enabled { 1 }

1;

__END__

=head1 NAME

Net::Server::PSGI - basic Net::Server based PSGI HTTP server class

=head1 TEST ONE LINER

    perl -e 'use base qw(Net::Server::PSGI); main->run(port => 8080)'

=cut
