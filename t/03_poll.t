use common::sense;

use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::HTTPD::Util;
use HTTP::Response;
use JSON;

use RPC::ExtDirect::Config;
use AnyEvent::HTTPD::ExtDirect;

use Test::More tests => 20;

# Test modules
use lib 't/lib';
use RPC::ExtDirect::Test::PollProvider;

my $dfile = 't/data/extdirect/poll';
my $tests = eval do { local $/; open my $fh, '<', $dfile; <$fh> } ## no critic
    or die "Can't eval $dfile: '$@'";

my $port = shift @ARGV || 19000 + int rand 100;

my $config = RPC::ExtDirect::Config->new(
    verbose_exceptions => 1,
    debug_serialize    => 1,
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
    my $poll_path        = $test->{poll_path};

    local $RPC::ExtDirect::Test::PollProvider::WHAT_YOURE_HAVING
                = $test->{password};

    $server->_set_callbacks(
        api_path    => $test->{api_path},
        router_path => $test->{router_path},
        poll_path   => $poll_path,
    );

    my $cv = AnyEvent::HTTPD::Util::test_connect(
        '127.0.0.1',
        $server->port,
        "GET $poll_path HTTP/1.0\r\n\r\n",
    );

    my $http_resp_str = $cv->recv;
    my $res = HTTP::Response->parse($http_resp_str);

    ok   $res,                              "$name not empty";
    is   $res->code,   $http_status,        "$name http status";
    like $res->content_type, $content_type, "$name content type";

    my $http_content = $res->content;

    # Remove whitespace
    s/\s//g for $expected_content, $http_content;

    is $http_content, $expected_content, "$name content"
        or diag explain $http_content;
};

