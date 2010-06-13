use strict;
use warnings;
use lib q(lib);
use AnyEvent::TFTPd::Connection;
use Test::More;

plan skip_all => 'Will not compile anymore';
plan tests => 37;

my $e = \%AnyEvent::TFTPd::Connection::ERROR_CODES;
my $port = 56789;
my $address = '127.0.0.1';
my $sent;

{
    my $c;
    eval { AnyEvent::TFTPd::Connection->new };
    like($@, qr{is required}, 'AnyEvent::TFTPd::Connection object failed to construct');

    eval {
        $c = AnyEvent::TFTPd::Connection->new(
                 server => server_obj(),
                 peername => peer_name(),
                 opcode => -1,
                 filehandle => undef,
             );
    };
    is($@, '', 'AnyEvent::TFTPd::Connection object constructed');

    is($c->address, $address, 'connection got address from peername');
    is($c->port, $port, 'connection got port from peername');
    ok(time - 5 <= $c->connected_at, 'connected_at is set');

    is($c->send_error, 1, 'error sent');
    is(
        $sent,
        pack('nnZ*',
            &AnyEvent::TFTPd::Connection::OPCODE_ERROR,
            @{ $e->{'not_defined'} }
        ),
        'error arrived'
    );
    $sent = '';

    is($c->send_packet, 0, 'fail to send packet');
    like($sent, qr{not found}, 'file was not found');
    $sent = '';
}

{
    my $data = 'x' x 600;
    open my $FH, '<', \$data;
    my $c = AnyEvent::TFTPd::Connection->new(
                server => server_obj(),
                peername => peer_name(),
                opcode => &AnyEvent::TFTPd::Connection::OPCODE_RRQ,
                filehandle => $FH,
            );

    is($c->send_packet, 1, 'packet 1 sent');
    like($sent, qr{^....xxxxxxxxxxxx}, 'packet 1 received');
    is(length $sent, 512 + 4, 'max packet length received');
    is($c->packet_number, 1, 'packet_number = 1');
    $sent = '';

    is($c->receive_ack(pack 'n', 1), 2, 'received ack 1 and sent last packet');
    like($sent, qr{^....xxxxxxxxxxxx}, 'packet 2 received');
    is(length $sent, 600 - 512 + 4, 'last packet received');
    is($c->packet_number, 2, 'packet_number = 2');
    $sent = '';

    is($c->receive_ack(pack 'n', 1), 2, 'received ack 1 and sent last packet again');
    is($c->retries, 2, 'retries has decended');
    is(length $sent, 600 - 512 + 4, 'last packet received');
    $sent = '';

    is($c->receive_ack(pack 'n', 2), -1, 'received ack 2 on last packet');
    is($c->packet_number, 3, 'packet_number = 3 does not exist');
    is($c->retries, 3, 'retries is restored');
    $sent = '';
}

{ # empty file
    my $data = '';
    open my $FH, '<', \$data;
    my $c = AnyEvent::TFTPd::Connection->new(
                server => server_obj(),
                peername => peer_name(),
                opcode => &AnyEvent::TFTPd::Connection::OPCODE_RRQ,
                filehandle => $FH,
            );

    is($c->send_packet, 2, 'packet 1 sent (empty)');
    is(length $sent, 4, 'empty packet received');
    is($c->packet_number, 1, 'packet_number = 1');
    $sent = '';

    is($c->receive_ack(pack 'n', 1), -1, 'received ack 1 on empty packet');
    $sent = '';
}

{
    my $recv = '';
    open my $FH, '>', \$recv;
    my $c = AnyEvent::TFTPd::Connection->new(
                server => server_obj(),
                peername => peer_name(),
                opcode => &AnyEvent::TFTPd::Connection::OPCODE_WRQ,
                filehandle => $FH,
            );

    is($c->receive_packet(pack 'na*', 1, 'x' x 512), 1, 'received first packet');
    is(
        $sent,
        pack('nn',
            &AnyEvent::TFTPd::Connection::OPCODE_ACK,
            1
        ),
        'sent ack 1'
    );
    is($recv, 'x' x 512, 'recv contains as expected');

    is($c->receive_packet(pack 'na*', 1, 'x' x 512), 1, 'received first packet again');
    is($c->retries, 2, 'retries has decended');
    is($recv, 'x' x 512, 'recv contains the same data');
    $sent = '';

    is($c->receive_packet(pack 'na*', 2, 'x' x 42), -1, 'received second and last packet');
    is($c->retries, 3, 'retries is restored');
    is($recv, 'x' x (512 + 42), 'recv contains the full data');
    is(
        $sent,
        pack('nn',
            &AnyEvent::TFTPd::Connection::OPCODE_ACK,
            2
        ),
        'sent ack 2'
    );
 
    $sent = '';
}

sub server_obj {
    unless(defined $sent) {
        eval q[
            package MockSocket;
            sub send { $sent .= $_[1] }

            package MockServer;
            sub socket { bless {}, 'MockSocket' }
            sub retries { 3 }

            $sent = q();

            1;
        ] or die $@;
    }

    return bless {}, 'MockServer';
}

sub peer_name {
    Socket::pack_sockaddr_in( $port, Socket::inet_aton($address) );
}
