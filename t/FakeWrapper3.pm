package FakeWrapper3;

# Wrapper around Net::Server::IP for testing

use strict;
use warnings;
use base qw(Net::Server::IP);

sub can_wrap3 {1}

1;
