package FakeWrapper1;

# Wrapper around IO::Socket::IP for testing

use strict;
use warnings;
use base qw(IO::Socket::IP);

sub can_wrap1 {1}

1;
