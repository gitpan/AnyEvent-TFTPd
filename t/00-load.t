#!/usr/bin/env perl
use lib qw(lib);
use Test::More;
plan tests => 2;
use_ok('AnyEvent::TFTPd');
use_ok('AnyEvent::TFTPd::Connection');
