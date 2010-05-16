use inc::Module::Install;

name q(AnyEvent-TFTPd);
all_from q(lib/AnyEvent/TFTPd.pm);

test_requires q(Test::More) => 0.94;

bugtracker q(http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-TFTPd);
homepage q(http://search.cpan.org/dist/AnyEvent-TFTPd);
repository q(git://github.com///github.com/);

# install_script glob('bin/*');
auto_install;
WriteAll;
