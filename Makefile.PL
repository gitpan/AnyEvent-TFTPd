use inc::Module::Install;

name q(AnyEvent-TFTPd);
all_from q(lib/AnyEvent/TFTPd.pm);

requires q(AnyEvent::Handle::UDP) => 0.01;
requires q(Moose) => 1.00;

test_requires q(AnyEvent) => 5.26;
test_requires q(Test::More) => 0.90;

bugtracker q(http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-TFTPd);
homepage q(http://search.cpan.org/dist/AnyEvent-TFTPd);
repository q(git://github.com/jhthorsen/anyevent-tftpd.git);

# install_script glob('bin/*');
# auto_install;
WriteAll;
