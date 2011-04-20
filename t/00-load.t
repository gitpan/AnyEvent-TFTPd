use lib qw(lib);
use Test::More;
plan tests => 3;
use_ok('AnyEvent::TFTPd');
use_ok('AnyEvent::TFTPd::CheckConnections');
use_ok('AnyEvent::TFTPd::Connection');
