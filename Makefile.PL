use 5.008000;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME => 'AnyEvent::HTTPD::ExtDirect',
    VERSION_FROM => 'lib/AnyEvent/HTTPD/ExtDirect.pm', # finds $VERSION
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'AnyEvent::HTTPD' => '0.93',
        'RPC::ExtDirect' => '2.12',
    },
    ABSTRACT => 'RPC::ExtDirect gateway for AnyEvent::HTTPD environment',
    AUTHOR => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE => 'perl',
    META_MERGE => {
        resources => {
            bugtracker => 'http://github.com/nohuhu/AnyEvent-HTTPD-ExtDirect/issues',
            repository => 'http://github.com/nohuhu/AnyEvent-HTTPD-ExtDirect',
        },
    },
);

