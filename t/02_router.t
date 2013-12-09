use common::sense;

use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::HTTPD::Util;
use HTTP::Request::Common;
use HTTP::Response;
use JSON;

use RPC::ExtDirect::Config;
use AnyEvent::HTTPD::ExtDirect;

use Test::More tests => 24;

# Test modules
use lib 't/lib';
use RPC::ExtDirect::Test::Foo;
use RPC::ExtDirect::Test::Bar;
use RPC::ExtDirect::Test::JuiceBar;
use RPC::ExtDirect::Test::Qux;
use RPC::ExtDirect::Test::PollProvider;

# Set the cheat flag for file uploads
local $RPC::ExtDirect::Test::JuiceBar::CHEAT = 1;

my $dfile = 't/data/extdirect/route';
my $tests = eval do { local $/; open my $fh, '<', $dfile; <$fh> } ## no critic
    or die "Can't eval $dfile: '$@'";

my $port = shift @ARGV || 19000 + int rand 100;

my $config = RPC::ExtDirect::Config->new(
    verbose_exceptions => 1,
    debug_serialize    => 1,
    no_polling         => 1,
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

    $server->_set_callbacks(
        api_path    => $test->{api_path},
        router_path => $test->{router_path},
        poll_path   => $test->{poll_path},
    );

    # Input content is HTTP::Request object
    my $text_content = $input_content->as_string( "\r\n" );

    my $cv = AnyEvent::HTTPD::Util::test_connect(
        '127.0.0.1',
        $server->port,
        $text_content,
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

done_testing;

sub raw_post {
    my ($url, $post) = @_;

    my $req = POST $url, Content => $post, Content_Type => 'application/json';
    $req->protocol('HTTP/1.0');
    
    return $req;
}

sub form_post {
    my ($url, @fields) = @_;

    my $req = POST $url, Content => [ @fields ];
    $req->protocol('HTTP/1.0');
    
    return $req;
}

sub form_upload {
    my ($url, $files, @fields) = @_;

    my $type = 'application/octet-stream';

    my $req = POST $url,
           Content_Type => 'form-data',
           Content      => [ @fields,
                             map {
                                    (   upload => [
                                            "t/data/cgi-data/$_",
                                            $_,
                                            'Content-Type' => $type,
                                        ]
                                    )
                                 } @$files
                           ]
    ;
    $req->protocol('HTTP/1.0');
    
    return $req;
}

