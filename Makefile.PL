use 5.008000;
use ExtUtils::MakeMaker;

# Add the `devtest` target to run regression and POD tests in one go
sub MY::postamble {
    return <<'END';
devtest :
	REGRESSION_TESTS=1 POD_TESTS=1 $(MAKE) test

END
}

# Override `disttest` so it would behave as `devtest`
sub MY::dist_test {
	return <<'END';
disttest : distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) devtest $(PASTHRU)

END
}

WriteMakefile(
    NAME => 'AnyEvent::HTTPD::ExtDirect',
    VERSION_FROM => 'lib/AnyEvent/HTTPD/ExtDirect.pm',
    BUILD_REQUIRES => {
        'Test::More' => 0,
		'URI'        => 0,
    },
    PREREQ_PM => {
        'AnyEvent::HTTPD' => '0.93',
        'RPC::ExtDirect'  => '3.0',
    },
    ABSTRACT => 'RPC::ExtDirect gateway for AnyEvent::HTTPD',
    AUTHOR => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE => 'perl',
    META_MERGE => {
        resources => {
            bugtracker => 'http://github.com/nohuhu/AnyEvent-HTTPD-ExtDirect/issues',
            repository => 'http://github.com/nohuhu/AnyEvent-HTTPD-ExtDirect',
        },
    },
);

