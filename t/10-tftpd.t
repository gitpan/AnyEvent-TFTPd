use strict;
use warnings;
use lib q(lib);
use AnyEvent;
use AnyEvent::TFTPd;
use Test::More;

plan tests => 25;
my($rbuf, $return_value);

$AnyEvent::TFTPd::DEBUG = 0;
build_classes();

my $s = AnyEvent::TFTPd->new(
            address => 'localhost',
            port => 12345,
            connection_class => 'TestConnection',
            max_connections => 1,
            _handle => TestHandle->new,
        );

{
    ok(eval { $s->setup }, 'connection is setup') or BAIL_OUT "failed to set up";
    ok($s->_handle->isa('AnyEvent::Handle::UDP'), '_handle is set up');

    my $c = TestConnection->new(
                peername => TestHandle::peername(),
                opcode => 0,
                server => $s,
            );

    is($s->add_connection($c), $c, 'add_connection()');
    is($s->get_connection($c->peername), $c, 'get_connection()');
    is($s->delete_connection($c), $c, 'delete_connection()');
}

{ # RRQ
    my $c = $s->on_connect(
                &AnyEvent::TFTPd::OPCODE_RRQ,
                join("\0", 'file1.bin', 'foomode', 'rfc1', 'rfc2'),
            );

    ok($c, 'on_connect() created RRQ connection');
    is($c->file, 'file1.bin', 'connection has the correct file');
    is($c->mode, 'foomode', 'connection has the correct mode');
    is_deeply($c->rfc, [qw/rfc1 rfc2/], 'connection has the correct rfc');
    is($s->get_all_connections, 1, 'one active connection');

    is($s->on_connect(
        &AnyEvent::TFTPd::OPCODE_RRQ,
        join("\0", 'file2.bin', 'barmode', 'rfcX', 'rfcY'),
    ), undef, 'on_connect() has reached max limit');

    $s->_clear_connections;

    $return_value = 255;
    $rbuf = pack('na*',
                &AnyEvent::TFTPd::OPCODE_RRQ,
                join("\0", 'file1.bin', 'foomode', 'rfc1', 'rfc2')
            );
    is($s->on_read($s->_handle), 1, 'on_read() created RRQ connection');

    $return_value = 1;
    $rbuf = pack 'nn', &AnyEvent::TFTPd::OPCODE_ACK, 1;
    is($s->on_read($s->_handle), 1, 'on_read() received ack for active connection');
    is($s->get_all_connections, 1, 'one active connection');

    $return_value = -1;
    $rbuf = pack 'nna*', &AnyEvent::TFTPd::OPCODE_ACK, 1, 'x' x 42;

    is($s->on_read($s->_handle), -1, 'on_read() received last ack for active connection');
    is($s->get_all_connections, 0, 'on_read() cleared connection');

    $s->_clear_connections;
}

{ # WRQ
    $return_value = 255;
    $rbuf = pack('na*',
                &AnyEvent::TFTPd::OPCODE_WRQ,
                join("\0", 'file1.bin', 'foomode', 'rfc1', 'rfc2')
            );
    is($s->on_read($s->_handle), 1, 'on_read() created WRQ connection');

    $return_value = 1;
    $rbuf = pack 'nna*', &AnyEvent::TFTPd::OPCODE_DATA, 1, 'x' x 512;
    is($s->on_read($s->_handle), 1, 'on_read() received data for active connection');
    is($s->get_all_connections, 1, 'one active connection');

    $return_value = -1;
    $rbuf = pack 'nn', &AnyEvent::TFTPd::OPCODE_DATA, 1;

    is($s->on_read($s->_handle), -1, 'on_read() received last packet for active connection');
    is($s->get_all_connections, 0, 'on_read() cleared connection');
}

{ # ERROR
    $return_value = 255;
    $rbuf = pack 'nnZ*', &AnyEvent::TFTPd::OPCODE_ERROR, 42, 'this is not the answer';
    is($s->on_read($s->_handle), 0, 'on_read() received data without a connection');

    $rbuf = pack 'na*', &AnyEvent::TFTPd::OPCODE_WRQ, join("\0", 'x', 'y');
    is($s->on_read($s->_handle), 1, 'on_read() created a connection');

    $rbuf = pack 'nnZ*', &AnyEvent::TFTPd::OPCODE_ERROR, 42, 'this is not the answer';
    is($s->on_read($s->_handle), 1, 'on_read() received error');

    $rbuf = pack 'nn', 42, 0;
    is($s->on_read($s->_handle), 0, 'on_read() received unknown opcode');
}

sub build_classes {
    eval q[
        package TestConnection;
        use Moose;
        extends 'AnyEvent::TFTPd::Connection';
        sub send_packet { $return_value }
        sub send_ack { $return_value }
        sub send_error { 255 }
        sub receive_packet { shift->send_ack }

        package TestHandle;
        use Moose;
        extends 'AnyEvent::Handle::UDP';
        sub new { my $class = shift; return bless {@_}, $class }
        sub rbuf :lvalue { $rbuf }
        sub peername {
            Socket::pack_sockaddr_in(
                56789,
                Socket::inet_aton("127.0.0.1")
            );
        }

        1;
    ] or die $@;
}
