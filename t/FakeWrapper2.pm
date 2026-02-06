package FakeWrapper2;

# Wrapper around IO::Socket::INET6 for testing

use strict;
use warnings;
use base qw(IO::Socket::INET6);

sub can_wrap2 {1}

1;
