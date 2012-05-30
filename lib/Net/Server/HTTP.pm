# -*- perl -*-
#
#  Net::Server::HTTP - Extensible Perl HTTP base server
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

package Net::Server::HTTP;

use strict;
use base qw(Net::Server::MultiType);
use Scalar::Util qw(weaken blessed);
use IO::Handle ();

sub net_server_type { __PACKAGE__ }

sub options {
    my $self = shift;
    my $ref  = $self->SUPER::options(@_);
    my $prop = $self->{'server'};
    $ref->{$_} = \$prop->{$_} for qw(timeout_header timeout_idle server_revision max_header_size);
    return $ref;
}

sub timeout_header  { shift->{'server'}->{'timeout_header'}  }
sub timeout_idle    { shift->{'server'}->{'timeout_idle'}    }
sub server_revision { shift->{'server'}->{'server_revision'} }
sub max_header_size { shift->{'server'}->{'max_header_size'} }

sub default_port { 80 }

sub default_server_type { 'Fork' }

sub post_configure {
    my $self = shift;
    $self->SUPER::post_configure(@_);
    my $prop = $self->{'server'};

    # set other defaults
    my $d = {
        timeout_header  => 15,
        timeout_idle    => 60,
        server_revision => __PACKAGE__."/$Net::Server::VERSION",
        max_header_size => 100_000,
    };
    $prop->{$_} = $d->{$_} foreach grep {!defined($prop->{$_})} keys %$d;

    return if $self->net_server_type ne __PACKAGE__;

    # install a callback that will handle our outbound header negotiation for the clients similar to what apache does for us
    my $copy = $self;
    $prop->{'tie_client_stdout'} = 1;
    $prop->{'tied_stdout_callback'} = sub {
        my $client = shift;
        my $method = shift;
        alarm($copy->timeout_idle); # reset timeout
        return $client->$method(@_) if ${*$client}{'headers_sent'};
        if ($method ne 'print') {
            $client->print("HTTP/1.0 501 Print\015\012Content-type:text/html\015\012\015\012Headers may only be sent via print method ($method)");
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
        if ($headers =~ m{^HTTP/1.[01] \s+ \d+ (?: | \s+ .+)\r?\n}x) {
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
            $copy->send_501("Not sure what type of headers to send - couldn't find valid headers");
        }
        return $client->print($headers);
    };
    weaken $copy;
}

sub send_status {
    my ($self, $status, $msg) = @_;
    $msg ||= ($status == 200) ? 'OK' : '-';
    $self->{'server'}->{'client'}->print(
        "HTTP/1.0 $status $msg\015\012",
        "Date: ".gmtime()." GMT\015\012",
        "Connection: close\015\012",
        "Server: ".$self->server_revision."\015\012",
    );
}

sub send_501 {
    my ($self, $err) = @_;
    $self->send_status(500, 'Died');
    $self->{'server'}->{'client'}->print(
        "Content-type: text/html\015\012\015\012",
        "<h1>Internal Server</h1>",
        "<p>$err</p>",
    );
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
    my $client = shift || $self->{'server'}->{'client'};

    local $SIG{'ALRM'} = sub { die "Server Timeout\n" };
    my $ok = eval {
        alarm($self->timeout_header);
        $self->process_headers($client);

        alarm($self->timeout_idle);
        $self->process_http_request($client);
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

sub script_name { shift->{'script_name'} || '' }

sub process_headers {
    my $self = shift;
    my $client = shift || $self->{'server'}->{'client'};

    $ENV{'REMOTE_PORT'} = $self->{'server'}->{'peerport'};
    $ENV{'REMOTE_ADDR'} = $self->{'server'}->{'peeraddr'};
    $ENV{'SERVER_PORT'} = $self->{'server'}->{'sockport'};
    $ENV{'SERVER_ADDR'} = $self->{'server'}->{'sockaddr'};
    $ENV{'HTTPS'} = 'on' if $self->{'server'}->{'client'}->NS_proto =~ /SSL/;

    my ($ok, $headers) = $client->read_until($self->max_header_size, qr{\n\r?\n});
    die "Could not parse http headers successfully\n" if $ok != 1;

    my ($req, @lines) = split /\r?\n/, $headers;
    if ($req !~ m{ ^\s*(GET|POST|PUT|DELETE|PUSH|HEAD|OPTIONS)\s+(.+)\s+HTTP/1\.[01]\s*$ }x) {
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
        $key = 'COOKIE' if $key eq 'COOKIES';
        $key =~ y/-/_/;
        $key =~ s/^\s+//;
        $key = "HTTP_$key" if $key !~ /^CONTENT_(?:LENGTH|TYPE)$/;
        $val =~ s/\s+$//;
        if (exists $ENV{$key}) {
            $ENV{$key} .= $val;
        } else {
            $ENV{$key} = $val;
        }
    }
}

sub process_http_request {
    my ($self, $client) = @_;
    print "Content-type: text/html\n\n";
    print "<form method=post action=/bam><input type=text name=foo><input type=submit></form>\n";
    if (eval { require Data::Dumper }) {
        local $Data::Dumper::Sortkeys = 1;
        my $form = {};
        if (eval { require CGI }) {  my $q = CGI->new; $form->{$_} = $q->param($_) for $q->param;  }
        print "<pre>".Data::Dumper->Dump([\%ENV, $form], ['*ENV', 'form'])."</pre>";
    }
}

1;

__END__

=head1 NAME

Net::Server::HTTP - very basic Net::Server based HTTP server class

=head1 TEST ONE LINER

    perl -e 'use base qw(Net::Server::HTTP); main->run(port => 8080)'

=head1 SYNOPSIS

    use base qw(Net::Server::HTTP);
    __PACKAGE__->run;

    sub process_http_request {
        my $self = shift;

        print "Content-type: text/html\n\n";
        print "<form method=post action=/bam><input type=text name=foo><input type=submit></form>\n";

        require Data::Dumper;
        local $Data::Dumper::Sortkeys = 1;

        require CGI;
        my $form = {};
        my $q = CGI->new; $form->{$_} = $q->param($_) for $q->param;

        print "<pre>".Data::Dumper->Dump([\%ENV, $form], ['*ENV', 'form'])."</pre>";
    }

=head1 DESCRIPTION

Even though Net::Server::HTTP doesn't fall into the normal parallel of
the other Net::Server flavors, handling HTTP requests is an often
requested feature and is a standard and simple protocol.

Net::Server::HTTP begins with base type MultiType defaulting to
Net::Server::Fork.  It is easy to change it to any of the other
Net::Server flavors by passing server_type => $other_flavor in the
server configurtation.  The port has also been defaulted to port 80 -
but could easily be changed to another through the server
configuration.  You can also very easily add ssl by including,
proto=>"ssl" and provide a SSL_cert_file and SSL_key_file.

=head1 METHODS

=over 4

=item C<process_http_request>

Will be passed the client handle, and will have STDOUT and STDIN tied
to the client.

During this method, the %ENV will have been set to a standard CGI
style environment.  You will need to be sure to print the Content-type
header.  This is one change from the other standard Net::Server base
classes.

During this method you can read from %ENV and STDIN just like a normal
HTTP request in other web servers.  You can print to STDOUT and
Net::Server will handle the header negotiation for you.

Note: Net::Server::HTTP has no concept of document root or script
aliases or default handling of static content.  That is up to the
consumer of Net::Server::HTTP to work out.

Net::Server::HTTP comes with a basic %ENV display installed as the
default process_http_request method.

=item C<process_request>

This method has been overridden in Net::Server::HTTP - you should not
use it while using Net::Server::HTTP.  This overridden method parses
the environment and sets up request alarms and handles dying failures.
It calls process_http_request once the request is ready and headers
have been parsed.

=item C<send_status>

Takes an HTTP status and a message.  Sends out the correct headers.

=item C<send_501>

Calls send_status with 501 and the argument passed to send_501.

=back

=head1 OPTIONS

In addition to the command line arguments of the Net::Server base
classes you can also set the following options.

=over 4

=item max_header_size

Defaults to 100_000.  Maximum number of bytes to read while parsing
headers.

=item server_revision

Defaults to Net::Server::HTTP/$Net::Server::VERSION.

=item timeout_header

Defaults to 15 - number of seconds to wait for parsing headers.

=item timeout_idle

Defaults to 60 - number of seconds a request can be idle before the
request is closed.

=back

=head1 TODO

Add support for writing out HTTP/1.1.

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
