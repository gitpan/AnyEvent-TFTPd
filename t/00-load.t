#!/usr/bin/env perl
use lib qw(lib);
use Test::More;
plan skip_all => 'Will not compile anymore';
plan tests => 3;
use_ok('AnyEvent::TFTPd');
use_ok('AnyEvent::TFTPd::CheckConnections');
use_ok('AnyEvent::TFTPd::Connection');
