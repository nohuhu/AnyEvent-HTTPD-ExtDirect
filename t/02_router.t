use common::sense;

use Getopt::Long;

use RPC::ExtDirect::Test::Pkg::Foo;
use RPC::ExtDirect::Test::Pkg::Bar;
use RPC::ExtDirect::Test::Pkg::JuiceBar;
use RPC::ExtDirect::Test::Pkg::Qux;
use RPC::ExtDirect::Test::Pkg::PollProvider;

use lib 't/lib';
use RPC::ExtDirect::Test::Util::AnyEvent;
use RPC::ExtDirect::Test::Data::Router;

use AnyEvent::HTTPD::ExtDirect;

my ($host, $port) = ('127.0.0.1', 19000 + int rand 100);
GetOptions('host=s' => \$host, 'port=i' => \$port);

my $tests = RPC::ExtDirect::Test::Data::Router::get_tests;

run_tests($tests, $host, $port, @ARGV);
