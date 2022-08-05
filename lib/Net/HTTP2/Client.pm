package Net::HTTP2::Client;

use strict;
use warnings;

=head1 NAME

Net::HTTP2::Client - Full-featured HTTP/2 client base class

=cut

# perl -I ../p5-X-Tiny/lib -MData::Dumper -MAnyEvent -I ../p5-IO-SigGuard/lib -I ../p5-Promise-ES6/lib -Ilib -MNet::HTTP2::Client -e'my $h2 = Net::HTTP2::Client->new(); my $cv = AnyEvent->condvar(); $h2->request("GET", "https://google.com")->then( sub { print Dumper shift } )->finally($cv); $cv->recv();'

#----------------------------------------------------------------------

use Carp ();
use URI::Split ();

use Net::HTTP2::Constants ();

use constant _SIMPLE_REDIRECTS => (
    301, 308,
    302, 307,
);

#----------------------------------------------------------------------

sub new {
    return bless {
        host_port_client => { },
    }, shift;
}

sub _split_uri_auth {
    my $auth = shift;

    if ( $auth =~ m<\A([^:]+):(.+)> ) {
        return ($1, $2);
    }

    return ($auth, Net::HTTP2::Constants::HTTPS_PORT);
}

sub request {
    my ($self, $method, $url, @opts_kv) = @_;

    # Omit the fragment:
    my ($scheme, $auth, $path, $query) = URI::Split::uri_split($url);

    if (!$scheme) {
        Carp::croak "Need absolute URL, not “$url”";
    }

    if ($scheme ne 'https') {
        Carp::croak "https only, not $scheme!";
    }

    my ($host, $port) = _split_uri_auth($auth);

    my $host_port_conn_hr = $self->{'host_port_client'};

    my $conn_ns = $self->_get_conn_namespace();

    my $path_and_query = $path;
    if (defined $query && length $query) {
        $path_and_query .= "?$query";
    }

    return _request_recurse(
        $conn_ns,
        $host_port_conn_hr,
        $method,
        $host,
        $port,
        $path_and_query,
        @opts_kv,
    );
}

sub _request_recurse {
    my ($conn_ns, $host_port_conn_hr, $method, $host, $port, $path_and_query, @opts_kv) = @_;

    my $conn = _get_conn( $conn_ns, $host_port_conn_hr, $host, $port, @opts_kv );

    return _request_once( $conn, $method, $path_and_query )->then(
        sub {
            my $resp = shift;

            my $status = $resp->status();
            my $redirect_yn = grep { $_ == $status } _SIMPLE_REDIRECTS;

            if ($status == 303) {
                $redirect_yn = 1;

                $method = 'GET';
                push @opts_kv, body => q<>;
            }

            if ($redirect_yn) {
                my ($new_host, $new_port, $path_and_query) = _consume_location(
                    $resp->headers()->{'location'},
                    $host, $port, $path_and_query,
                );

                $host = $new_host;
                $port = $new_port;

                return _request_recurse( $conn_ns, $host_port_conn_hr, $method, $host, $port, $path_and_query, @opts_kv );
            }

            return $resp;
        }
    );
}

sub _consume_location {
    my ($location, $host, $port, $old_path) = @_;

    my ($scheme, $auth, $path, $query) = URI::Split::uri_split($location);

    my $path_and_query = $path;
    if (defined $query && length $query) {
        $path_and_query .= "?$query";
    }

    if ($scheme) {
        if ($scheme ne 'https') {
            Carp::croak "Invalid scheme in redirect: $location";
        }

        ($host, $port) = _split_uri_auth($auth);
    }

    if (rindex($path, '/', 0) != 0) {
        $old_path =~ s<(.*)/><$1>;
        substr( $path_and_query, 0, 0, "$old_path/" );
    }

    return ($host, $port, $path_and_query);
}

sub _get_conn {
    my ($conn_ns, $host_port_conn_hr, $host, $port) = @_;

    return $host_port_conn_hr->{$host}{$port || q<>} ||= $conn_ns->new(
        $host,
        ($port == Net::HTTP2::Constants::HTTPS_PORT ? () : (port => $port)),
    );
}

sub _request_once {
    my ($conn, $method, $path_and_query, @opts_kv) = @_;

    return $conn->request($method, $path_and_query);
}

sub _get_conn_namespace {
    my $self = shift;

    return $self->{'_conn_ns'} ||= do {
        my $ns = "Net::HTTP2::Client::Connection::" . $self->_CLIENT_IO();

        local $@;
        Carp::croak $@ if !eval "require $ns";

        $ns;
    };
}

1;
