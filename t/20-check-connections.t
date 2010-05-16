use strict;
use warnings;
use lib q(lib);
use AnyEvent;
use AnyEvent::TFTPd;
use AnyEvent::TFTPd::CheckConnections;
use Test::More;

plan tests => 12;
build_classes();
$AnyEvent::TFTPd::DEBUG = 1;
my @log;

AnyEvent::TFTPd::CheckConnections->meta->apply(AnyEvent::TFTPd->meta);

my $s = AnyEvent::TFTPd->new(
            address => 'localhost',
            port => 12345,
            connection_class => 'TestConnection',
            max_connections => 1,
            timeout => 1,
            retries => 1,
            _handle => TestHandle->new,
        );

{
    my $c = TestConnection->new(
                peername => TestHandle::peername(),
                last_seen_peer => time,
                opcode => 0,
                server => $s,
            );

    ok(eval { $s->setup(timeout => 3) }, 'connection is setup') or BAIL_OUT "failed to set up";
    is($s->timeout, 3, 'timeout was modified inside setup()');
    is($s->add_connection($c), $c, 'connection was added');

    is($s->check_connections, 0, 'no connections has timed out');

    $c->last_seen_peer(time - 10);
    is($s->check_connections, 0, 'last_seen_peer exceeded?');
    like($log[1], qr{Timeout}, 'last_seen_peer has exceeded');
    is($c->retries, 0, 'retries = 0');
    is($s->get_all_connections, 1, 'connection is still alive');

    is($s->check_connections, 1, 'last_seen_peer exceeded?');
    like($log[1], qr{Retries}, 'retries has exceeded');
    is($c->retries, -1, 'retries is -1');
    is($s->get_all_connections, 0, 'connection got removed');
}

sub build_classes {
    eval q[
        package TestConnection;
        use Moose;
        extends 'AnyEvent::TFTPd::Connection';
        sub send_packet {}
        sub send_ack {}
        sub logf { shift; @log = @_ }

        package TestHandle;
        use Moose;
        extends 'AnyEvent::Handle::UDP';
        sub new { my $class = shift; return bless {@_}, $class }
        sub peername {
            Socket::pack_sockaddr_in(
                56789,
                Socket::inet_aton("127.0.0.1")
            );
        }

        1;
    ] or die $@;
}
