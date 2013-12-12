use common::sense;

use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::HTTPD::Util;
use HTTP::Response;
use JSON;

use RPC::ExtDirect::Test::Util;

use RPC::ExtDirect::Config;

use Test::More tests => 13;

BEGIN { use_ok 'AnyEvent::HTTPD::ExtDirect'; }

# Test modules
use lib 't/lib';
use RPC::ExtDirect::Test::Foo;
use RPC::ExtDirect::Test::Bar;
use RPC::ExtDirect::Test::Qux;
use RPC::ExtDirect::Test::PollProvider;

my $dfile = 't/data/extdirect/api';
my $tests = eval do { local $/; open my $fh, '<', $dfile; <$fh> } ## no critic
    or die "Can't eval $dfile: '$@'";

my $port = shift @ARGV || 19000 + int rand 100;

my $config = RPC::ExtDirect::Config->new(
    debug_serialize => 1,
    no_polling      => 1,
);

my $server = AnyEvent::HTTPD::ExtDirect->new(
    port   => $port,
    host   => '127.0.0.1',
    config => $config,
);

for my $test ( @$tests ) {
    my $name             = $test->{name};
    my $url              = $test->{plack_url};
    my $method           = $test->{method};
    my $input_content    = $test->{input_content};
    my $plack_input      = $test->{plack_input};
    my $http_status      = $test->{http_status};
    my $content_type     = $test->{content_type};
    my $expected_content = $test->{expected_content};

    if ( defined $plack_input ) {
        my %input = @$plack_input;

        while ( my ($key, $value) = each %input ) {
            $config->$key($value);
        }
    }

    $server->_set_callbacks(
        api_path    => $test->{api_path},
        router_path => $test->{router_path},
        poll_path   => $test->{poll_path},
    );

    my $cv = AnyEvent::HTTPD::Util::test_connect(
        '127.0.0.1',
        $server->port,
        GET_str($test, $server->port),
    );
    
    my $http_resp_str = $cv->recv;
    my $res = HTTP::Response->parse($http_resp_str);

    ok   $res,                              "$name not empty";
    is   $res->code,   $http_status,        "$name http status";
    like $res->content_type, $content_type, "$name content type";
 
    my $http_content = $res->content;

    # Deparse both actual and expected content
    my $actual_data   = deparse_api($http_content);
    my $expected_data = deparse_api($expected_content);

    is_deeply $actual_data,, $expected_data, "$name content"
        or diag explain $actual_data;
};

sub GET_str {
    my ($test, $port) = @_;

    my $plack_url = $test->{plack_url};
    $plack_url =~ s/^\/+//;

    my $url    = sprintf "http://localhost:%d/%s", $port, $plack_url;
    my $method = $test->{method};

    return sprintf "%s %s HTTP/1.0\r\n\r\n", uc $method, $url;
}

done_testing;
