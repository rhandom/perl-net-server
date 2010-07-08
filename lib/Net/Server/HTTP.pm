package Net::Server::HTTP;

=head1 NAME

Net::Server::HTTP - very basic Net::Server based HTTP server class

=cut

use strict;
use warnings;
use base qw(Net::Server::MultiType);
use vars qw($VERSION);
use Scalar::Util qw(weaken);

$VERSION = $Net::Server::VERSION; # done until separated

sub options {
  my ($self, $ref) = @_;
  my $prop = $self->{server};
  $self->SUPER::options($ref);

  foreach ( qw(timeout_header
               timeout_idle
               server_revision
               ) ){
    $prop->{$_} = undef unless exists $prop->{$_};
    $ref->{$_} = \$prop->{$_};
  }
}

### make sure some defaults are set
sub post_configure {
  my $self = shift;
  my $prop = $self->{server};
  $self->SUPER::post_configure;

  my $d = {
    timeout_header  => 15,
    timeout_idle    => 60,
    server_revision => __PACKAGE__."/$VERSION",
  };
  $prop->{$_} = $d->{$_} foreach grep {!defined($prop->{$_})} keys %$d;
}

sub timeout_header  { shift->{server}->{timeout_header} }
sub timeout_idle    { shift->{server}->{timeout_idle} }
sub server_revision { shift->{server}->{server_revision} }

sub default_port { 80 }

sub default_server_type { 'Fork' }

sub pre_bind {
    my $self = shift;
    my $prop = $self->{'server'};

    # install a callback that will handle our outbound header negotiation for the clients similar to what apache does for us
    my $copy = $self;
    $prop->{'tie_client_stdout'} = 1;
    $prop->{'tied_stdout_callback'} = sub {
        my $client = shift;
        my $method = shift;
        alarm($copy->timeout_idle); # reset timeout
        return $client->$method(@_) if ${*$client}{'headers_sent'};
        if ($method ne 'print') {
            $client->print("HTTP/1.0 501 Print\r\nContent-type:text/html\r\n\r\nHeaders may only be sent via print method ($method)");
            die "All headers must be done via print";
        }
        my $headers = ${*$client}{'headers'} || '';
        $headers .= join '', @_;
        if ($headers !~ /\n\r?\n/) { # headers aren't finished yet
            ${*$client}{'headers'} = $headers;
            return;
        }
        ${*$client}{'headers_sent'} = 1;
        delete ${*$client}{'headers'};
        if ($headers =~ m{^HTTP/1.[01] \s+ \d+ (?: | \s+ .+)\r?\n}) {
            # looks like they are sending their own status
        }
        elsif ($headers =~ /^Status:\s+(\d+) (?:|\s+(.+?))\s*$/im) {
            $copy->send_status($1, $2 || '-');
        }
        elsif ($headers =~ /^Location:\s+/im) {
            $copy->send_status(302, 'bouncing');
        }
        elsif ($headers =~ /^Content-type:\s+\S.*/im) {
            $copy->send_status(200, 'OK');
        }
        else {
            $copy->send_501("Not sure what type of headers to send for <xmp style=color:red>$_[0]</xmp>");
        }
        return $client->print($headers);
    };
    weaken $copy;

    return $self->SUPER::pre_bind(@_);
}

sub send_status {
    my ($self, $status, $msg) = @_;
    $msg ||= ($status == 200) ? 'OK' : '-';
    print "HTTP/1.0 $status $msg\r\n";
    print "Date: ".gmtime()." GMT\r\n";
    print "Connection: close\r\n";
    print "Server: ".$self->server_revision."\r\n";
}

sub send_501 {
    my ($self, $err) = @_;
    $self->send_status(500, 'Died');
    print "Content-type: text/html\r\n\r\n";
    print "<h1>Internal Server</h1>";
    print "<p>$err</p>";
}

###----------------------------------------------------------------###

sub get_client_info {
    my $self = shift;
    $self->SUPER::get_client_info(@_);
    $self->clear_http_env;
}

sub clear_http_env {
    my $self = shift;
    %ENV = ();
}

sub process_request {
    my $self = shift;

    local $SIG{'ALRM'} = sub { die "Server Timeout\n" };
    my $ok = eval {
        alarm($self->timeout_header);
        $self->process_headers;

        alarm($self->timeout_idle);
        $self->process_http_request;
        alarm(0);
        1;
    };
    alarm(0);

    if (! $ok) {
        my $err = "$@" || "Something happened";
        $self->send_501($err);
        die $err;
    }
}

sub script_name { shift->{'script_name'} || $0 }

sub process_headers {
    my $self = shift;

    $ENV{'REMOTE_PORT'} = $self->{'server'}->{'peerport'};
    $ENV{'REMOTE_ADDR'} = $self->{'server'}->{'peeraddr'};
    $ENV{'SERVER_PORT'} = $self->{'server'}->{'sockport'};
    $ENV{'SERVER_ADDR'} = $self->{'server'}->{'sockaddr'};
    $ENV{'HTTPS'} = 'on' if $self->{'server'}->{'client'}->NS_proto eq 'SSLEAY';

    my ($ok, $headers) = $self->{'server'}->{'client'}->read_until(100_000, qr{\n\r?\n});
    die "Couldn't parse headers successfully" if $ok != 1;

    my ($req, @lines) = split /\r?\n/, $headers;
    if ($req !~ m{ ^\s*(GET|POST|PUT|DELETE|PUSH|HEAD)\s+(.+)\s+HTTP/1\.[01]\s*$ }x) {
        die "Invalid request\n";
    }
    $ENV{'REQUEST_METHOD'} = $1;
    $ENV{'REQUEST_URI'}    = $2;
    $ENV{'QUERY_STRING'}   = $1 if $ENV{'REQUEST_URI'} =~ m{ \?(.*)$ }x;
    $ENV{'PATH_INFO'}      = $1 if $ENV{'REQUEST_URI'} =~ m{^([^\?]+)};
    $ENV{'SCRIPT_NAME'}    = $self->script_name($ENV{'PATH_INFO'}) || '';
    my $type = $Net::Server::HTTP::ISA[0];
    $type = $Net::Server::MultiType::ISA[0] if $type eq 'Net::Server::MultiType';
    $ENV{'NET_SERVER_TYPE'} = $type;
    $ENV{'NET_SERVER_SOFTWARE'} = $self->server_revision;

    foreach my $l (@lines) {
        my ($key, $val) = split /\s*:\s*/, $l, 2;
        $key = uc($key);
        $key =~ y/-/_/;
        $key =~ s/^\s+//;
        $key = "HTTP_$key" if $key ne 'CONTENT_LENGTH';
        $val =~ s/\s+$//;
        $ENV{$key} = $val;
    }
}

sub process_http_request {
    my $self = shift;
    print "Content-type: text/html\n\n";
    print "<form method=post action=/bam><input type=text name=foo><input type=submit></form>";

    if (require Data::Dumper) {
        local $Data::Dumper::Sortkeys = 1;
        my $form = {};
        if (require CGI) {  my $q = CGI->new; $form->{$_} = $q->param($_) for $q->param;  }
        print "<pre>".Data::Dumper->Dump([\%ENV, $form], ['*ENV', 'form'])."</pre>";
    }
}

1;

__END__

=HEAD SYNOPSIS

    use base qw(Net::Server::HTTP);
    __PACKAGE__->run;

    sub process_http_request {
        my $self = shift;

        print "Content-type: text/html\n\n";
        print "<form method=post action=/bam><input type=text name=foo><input type=submit></form>";

        if (require Data::Dumper) {
            local $Data::Dumper::Sortkeys = 1;
            my $form = {};
            if (require CGI) {  my $q = CGI->new; $form->{$_} = $q->param($_) for $q->param;  }
            print "<pre>".Data::Dumper->Dump([\%ENV, $form], ['*ENV', 'form'])."</pre>";
        }
    }

=head1 DESCRIPTION

Even though Net::Server::HTTP doesn't fall into the normal parallel of the other Net::Server flavors,
handling HTTP requests is an often requested feature and is a standard and simple protocol.

Net::Server::HTTP begins with base type MultiType defaulting to Net::Server::Fork.  It is easy
to change it to any of the other Net::Server flavors by passing server_type => $other_flavor in the
server configurtation.  The port has also been defaulted to port 80 - but could easily be changed to
another through the server configuration.

=head1 METHODS

=over 4

=item C<process_http_request>

During this method, the %ENV will have been set to a standard CGI style environment.  You will need to
be sure to print the Content-type header.  This is one change from the other standard Net::Server
base classes.

During this method you can read from ENV and STDIN just like a normal HTTP request in other web servers.
You can print to STDOUT and Net::Server will handle the header negotiation for you.

Note: Net::Server::HTTP has no concept of document root or script aliases or default handling of
static content.  That is up to the consumer of Net::Server::HTTP to work out.

Net::Server::HTTP comes with a basic ENV display installed as the default process_request method.

=item C<process_request>

This method has been overridden in Net::Server::HTTP - you should not use it while using Net::Server::HTTP.
This method parses the environment and sets up request alarms and handles dying failures.  It calls
process_http_request once the request is ready.

=head1 COMMAND LINE ARGUMENTS

In addition to the command line arguments of the Net::Server
base classes you can also set the following options.

=over 4

=item server_revision

Defaults to Net::Server::HTTP/$Net::Server::VERSION.

=item timeout_header

Defaults to 15 - number of seconds to wait for parsing headers.

=item timeout_idle

Defaults to 60 - number of seconds a request can be idle before
the request is closed.

=back

=head1 TODO

Add support for HTTP/1.1

=head1 AUTHOR

Paul T. Seamons paul@seamons.com

=head1 THANKS

See L<Net::Server>

=head1 SEE ALSO

Please see also
L<Net::Server::Fork>,
L<Net::Server::INET>,
L<Net::Server::PreFork>,
L<Net::Server::PreForkSimple>,
L<Net::Server::MultiType>,
L<Net::Server::Single>
L<Net::Server::SIG>
L<Net::Server::Daemonize>
L<Net::Server::Proto>

=cut
