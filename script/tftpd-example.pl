#!/usr/bin/env perl

use strict;
use warnings;
use lib q(lib);
#use Coro; # 3
#use EV; # 3
#use POE; # 6
#use Event; # 5.7
use AnyEvent;
use AnyEvent::TFTPd;
use Test::More;

$AnyEvent::TFTPd::DEBUG = 1;

my $tftpd = AnyEvent::TFTPd->new(
                address => 'localhost',
                port => 12345,
                connection_class => 'AnyEvent::TFTPd::Connection',
                max_connections => 10,
            )->setup or die $@;

print "tftpd-example.pl waits for connections...\n";
AnyEvent->condvar->recv;
exit 0;
