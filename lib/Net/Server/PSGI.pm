# -*- perl -*-
#
#  Net::Server::PSGI - Extensible Perl HTTP PSGI base server
#
#  $Id$
#
#  Copyright (C) 2011-2012
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

sub net_server_type { __PACKAGE__ }

sub options {
    my $self = shift;
    my $ref  = $self->SUPER::options(@_);
    my $prop = $self->{'server'};
    $ref->{$_} = \$prop->{$_} for qw(app);
    return $ref;
}

sub post_configure {
    my $self = shift;
    my $prop = $self->{'server'};

    $prop->{'log_handle'} = IO::Handle->new;
    $prop->{'log_handle'}->fdopen(fileno(STDERR), "w");
    $prop->{'no_client_stdout'} = 1;

    $self->SUPER::post_configure(@_);
}

sub process_request {
    my $self = shift;

    local $SIG{'ALRM'} = sub { die "Server Timeout\n" };
    my $ok = eval {
        alarm($self->timeout_header);
        $self->process_headers;

        alarm($self->timeout_idle);
        my $env = \%ENV;
        $env->{'psgi.version'}      = [1, 0];
        $env->{'psgi.url_scheme'}   = ($ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on') ? 'https' : 'http';
        $env->{'psgi.input'}        = $self->{'server'}->{'client'};
        $env->{'psgi.errors'}       = $self->{'server'}->{'log_handle'};
        $env->{'psgi.multithread'}  = 1;
        $env->{'psgi.multiprocess'} = 1;
        $env->{'psgi.nonblocking'}  = 1; # need to make this false if we aren't of a forking type server
        $env->{'psgi.streaming'}    = 1;
        local %ENV;
        $self->process_psgi_request($env);
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

sub process_psgi_request {
    my ($self, $env) = @_;
    my $app = $self->find_psgi_handler($env);
    my $resp = $app->($env);
    return $resp->(sub {
        my $resp = shift;
        $self->print_psgi_headers($resp->[0], $resp->[1]);
        return $self->{'server'}->{'client'} if @$resp == 2;
        return $self->print_psgi_body($resp->[2]);
    }) if ref($resp) eq 'CODE';
    $self->print_psgi_headers($resp->[0], $resp->[1]);
    $self->print_psgi_body($resp->[2]);
}

sub find_psgi_handler { shift->app || \&psgi_echo_handler }

sub app {
    my $self = shift;
    $self->{'server'}->{'app'} = shift if @_;
    return $self->{'server'}->{'app'};
}

sub print_psgi_headers {
    my ($self, $status, $headers) = @_;
    my $client = $self->{'server'}->{'client'};
    $self->send_status($status);
    $client->print($headers->[$_*2],': ', $headers->[$_*2 + 1], "\015\012") for 0 .. @{ $headers || [] } / 2 - 1;
    $client->print("\015\012");
}

sub print_psgi_body {
    my ($self, $body) = @_;
    my $client = $self->{'server'}->{'client'};
    if (ref $body eq 'ARRAY') {
        $client->print(@$body);
    } elsif (blessed($body) && $body->can('getline')) {
        $client->print($_) while defined($_ = $body->getline);
    } else {
        $client->print(<$body>);
    }
}

sub psgi_echo_handler {
    my $env = shift;
    my $txt = qq{<form method="post" action="/bam"><input type="text" name="foo"><input type="submit"></form>\n};
    if (eval { require Data::Dumper }) {
        local $Data::Dumper::Sortkeys = 1;
        my $form = {};
        if (eval { require CGI::PSGI }) {  my $q = CGI::PSGI->new($env); $form->{$_} = $q->param($_) for $q->param;  }
        $txt .= "<pre>".Data::Dumper->Dump([$env, $form], ['env', 'form'])."</pre>";
    }
    return [200, ['Content-type', 'text/html'], [$txt]];
}

1;

__END__

=head1 NAME

Net::Server::PSGI - basic Net::Server based PSGI HTTP server class

=head1 TEST ONE LINER

    perl -e 'use base qw(Net::Server::PSGI); main->run(port => 8080, ipv => "*")'

=head1 SYNOPSIS

    use base qw(Net::Server::PSGI);
    __PACKAGE__->run(app => \&my_echo_handler); # will bind IPv4 port 80

    sub my_echo_handler {
        my $env = shift;
        my $txt = qq{<form method="post" action="/bam"><input type="text" name="foo"><input type="submit"></form>\n};

        require Data::Dumper;
        local $Data::Dumper::Sortkeys = 1;

        require CGI::PSGI;
        my $form = {};
        my $q = CGI::PSGI->new($env);
        $form->{$_} = $q->param($_) for $q->param;

        $txt .= "<pre>".Data::Dumper->Dump([$env, $form], ['env', 'form'])."</pre>";

        return [200, ['Content-type', 'text/html'], [$txt]];
    }

=head1 DESCRIPTION

Net::Server::PSGI takes Net::Server::HTTP one level farther.  It
begins with base type MultiType defaulting to Net::Server::Fork.  It
is easy to change it to any of the other Net::Server flavors by
passing server_type => $other_flavor in the server configurtation.
The port has also been defaulted to port 80 - but could easily be
changed to another through the server configuration.  You can also
very easily add ssl by including, proto=>"ssl" and provide a
SSL_cert_file and SSL_key_file.

If you want a more fully featured PSGI experience, it would be wise
to look at the L<Plack> and L<Starman> set of modules.

=head1 METHODS

=over 4

=item C<process_request>

This method has been overridden in Net::Server::PSGI - you should not
use it while using Net::Server::PSGI.  This overridden method parses
the environment and sets up request alarms and handles dying failures.
It calls process_psgi_request once the request is ready and headers
have been parsed.

=item C<process_psgi_request>

Used when psgi_enabled is true.  During this method, find_psgi_handler
will be called to return the appropriate psgi response handler.  Once
finished, print_psgi_headers and print_psgi_body are used to print out
the response.  See L<PSGI>.

Typically this method should not be overridden.  Instead, an appropriate
method for finding the app should be given to find_psgi_handler or app.

=item C<find_psgi_handler>

Used to lookup the appropriate PSGI handler.  A reference to the
already parsed $env hashref is passed.  PATH_INFO will be initialized
to the full path portion of the URI.  SCRIPT_NAME will be initialized
to the empty string.  This handler should set the appropriate values
for SCRIPT_NAME and PATH_INFO depending upon the path matched.  A code
reference for the handler should be returned.  The default
find_psgi_handler will call the C<app> method.  If that fails a
reference to the psgi_echo_handler is returned as the default
application.

    sub find_psgi_handler {
        my ($self, $env) = @_;
        if ($env->{'REQUEST_URI'} =~ m{^ /foo \b ($ |/.*$ ) }x) {
            $env->{'PATH_INFO'} = $1;
            return \&foo_app;
        } else {
            return $self->SUPER::find_psgi_handler($env);
        }
    }

=item C<app>

Return a reference to the application being served.  This should
be a valid PSGI application.  See L<PSGI>.  By default it will look
at the value of the C<app> configuration option.  The C<app> method
may also be used to set the C<app> configuration option.

    package MyApp;
    use base qw(Net::Server::PSGI);

    sub default_server_type { 'Prefork' }

    sub my_app {
        my $env = shift;
        return [200, ['Content-type', 'text/html'], ["Hello world"]];
    }


    MyApp->run(app => \&my_app);


    # OR
    sub app { \&my_app }
    MyApp->run;


    # OR
    my $server = MyApp->new;
    $server->app(\&my_app);
    $server->run;

=back

=head1 OPTIONS

In addition to the command line arguments of the Net::Server::HTTP
base classes you can also set the following options.

=over 4

=item app

Should return a coderef of the PSGI application.  Is returned by the
app method.

=back

=head1 AUTHOR

Paul T. Seamons paul@seamons.com

=head1 SEE ALSO

Please see also
L<Plack>,
L<Starman>,

L<Net::Server::Fork>,
L<Net::Server::INET>,
L<Net::Server::PreFork>,
L<Net::Server::PreForkSimple>,
L<Net::Server::MultiType>,
L<Net::Server::Single>
L<Net::Server::SIG>
L<Net::Server::Daemonize>
L<Net::Server::Proto>
L<Net::Server::HTTP>

=cut

