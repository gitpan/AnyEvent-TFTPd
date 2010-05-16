package AnyEvent::TFTPd::Connection;

=head1 NAME

AnyEvent::TFTPd::Connection - Represents one connection to TFTPd

=head1 DESCRIPTION

=head1 SYNOPSIS

=cut

use Moose;
use Socket;

use constant MIN_BLKSIZE => 512;
use constant OPCODE_RRQ => 1;
use constant OPCODE_WRQ => 2;
use constant OPCODE_DATA => 3;
use constant OPCODE_ACK => 4;
use constant OPCODE_ERROR => 5;
use constant OPCODE_OACK => 6;

use overload (
    q("") => sub { $_[0]->peername },
    fallback => 1,
);

our %ERROR_CODES = (
    not_defined         => [0, 'Not defined, see error message'],
    unknown_opcode      => [0, 'Unknown opcode: %s'],
    no_connection       => [0, 'No connection'],
    file_not_found      => [1, 'File not found'],
    access_violation    => [2, 'Access violation'],
    disk_full           => [3, 'Disk full or allocation exceeded'],
    illegal_operation   => [4, 'Illegal TFTP operation'],
    unknown_transfer_id => [5, 'Unknown transfer ID'],
    file_exists         => [6, 'File already exists'],
    no_such_user        => [7, 'No such user'],
);

=head1 ATTRIBUTES

=head2 peername

Holds the sockaddr of the remote host.

=cut

has peername => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=head2 address

Holds a human readable version of the address part of L</peername>.

=cut

has address => (
    is => 'ro',
    isa => 'Str',
    init_arg => undef,
    lazy => 1,
    default => sub { inet_ntoa +(sockaddr_in $_[0]->peername )[1] },
);

=head2 port

Holds a human readable version of the port part of L</peername>.

=cut

has port => (
    is => 'ro',
    isa => 'Int',
    init_arg => undef,
    lazy => 1,
    default => sub { (sockaddr_in $_[0]->peername )[0] },
);

=head2 opcode

A numeric representation of the opcode which initiated the connection.

=cut

has opcode => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

=head2 mode

Either "ascii" or "octet" or empty string if unknown.

=cut

has mode => (
    is => 'ro',
    isa => 'Str',
    default => '',
);

=head2 file

A string representing the requested file from client.

=cut

has file => (
    is => 'ro',
    isa => 'Str',
    default => '',
);

=head2 filehandle

The filehandle used to read/write data from/to client.

=cut

has filehandle => (
    is => 'rw',
    isa => 'Maybe[GlobRef]',
    lazy_build => 1,
);

sub _build_filehandle {
    my $self = shift;
    my $mode = $self->opcode eq OPCODE_WRQ ? '>' : '<';
    my $file = $self->file;
    my $FH;

    if($mode eq '<') {
        if(!-r $file) {
            $self->logf(warn => 'File cannot be read: %s', $file);
            return;
        }
    }
    else {
        if(-e $file) {
            $self->logf(warn => 'File exists: %s', $file);
            return;
        }
    }

    unless(open $FH, $mode, $file) {
        $self->logf(error => 'Read %s: %s', $file, $!);
        return;
    }

    return $FH;
}

=head2 rfc

Contains extra parameters the client has provided. These parameters are
stored in a hash ref.

=cut

has rfc => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
);

=head2 server

A reference back to the L<AnyEvent::TFTPd> object.

=cut

has server => (
    is => 'ro',
    isa => 'Object',
    required => 1,
    handles => [qw/ socket /],
);

=head2 connected_at

The time the connection was established. Epoch timestamp.

=cut

has connected_at => (
    is => 'ro',
    isa => 'Int',
    default => sub { time },
);

=head2 packet_number

The current packet number received/sent.

=cut

has packet_number => (
    is => 'ro',
    isa => 'Int',
    traits => ['Counter'],
    default => 1,
    handles => {
        inc_packet_number => 'inc',
    },
);

=head2 retries

The number of retries left before aborting the transmission.

=cut

has retries => (
    is => 'ro',
    isa => 'Int',
    default => 0,
    handles => {
        dec_retries => 'dec',
    },
);

=head1 METHODS

=head2 send_packet

This method will send a packet of data from L</filehandle>
to client, identified by L</peername>. The packet is calculated
using the C<MIN_BLKSIZE> and L</packet_number>. Returns 1 on
success, 2 if this is the last packet to be sent, 0 if something
went wrong and -1 no more data is available from filehandle.

=cut

sub send_packet {
    my $self = shift;
    my $FH = $self->filehandle;
    my $n = $self->packet_number;
    my $data;

    if(not $FH) {
        $self->send_error('file_not_found');
        return 0;
    }
    if(not seek $FH, ($n - 1) * MIN_BLKSIZE, 0) {
        $self->logf(error => 'Seek %s: %s', $self->file, $!);
        $self->send_error('file_not_found');
        return 0;
    }
    if(not defined read $FH, $data, MIN_BLKSIZE) {
        $self->logf(error => 'Read %s: %s', $self->file, $!);
        $self->send_error('file_not_found');
        return 0;
    }
    if(0 == length $data and 1 < $self->packet_number) {
        $self->logf(debug => 'Peer has successfully received %s', $self->file);
        return -1;
    }

    $self->socket->send(
        pack('nna*', OPCODE_DATA, $self->packet_number, $data),
        MSG_DONTWAIT,
        $self->peername,
    ) or do {
        $self->logf(error => 'Send %s: %s', $self->file, $!);
        return 0;
    };

    #$self->logf(trace => 'Sent packet n=%i', $self->packet_number);

    return length $data < MIN_BLKSIZE ? 2 : 1;
}

=head2 receive_ack

This method will receive a datagram and unwraps the packet number from
it using C<unpack("n")>. It will increase the L</packet_number> if
the received packet number matches L</packet_number>.

Will always call L</send_packet> and return the value it returns. A
return value of -1 indicates that the last ACK was received and the
connection can be "shut down".

=cut

sub receive_ack {
    my $self = shift;
    my($n) = unpack 'n', shift;

    if($n == $self->packet_number) {
        #$self->logf(trace => 'Received ack n=%i', $n);
        $self->inc_packet_number;
    }
    else {
        $self->logf(warn => 'Wrong packet number: %i != %i', $n, $self->packet_number);
    }

    return $self->send_packet;
}

=head2 receive_packet

This method will receive a datagram and unwraps the packet number and
body from it using C<unpack("na*")>. It stores the data in the current
filehandle if the packet number equals L</packet_number>. It returns
1 on success, 0 on failure and -1 if this was the last packet to be
received. The latter indicates that it is safe for this connection to
"shut down".

=cut

sub receive_packet {
    my $self = shift;
    my($n, $data) = unpack 'na*', shift;
    my $FH = $self->filehandle;

    unless($FH) {
        $self->send_error('illegal_operation');
        return 0;
    }
    unless($n == $self->packet_number) {
        $self->logf(warn => 'Wrong packet number: %i != %i', $n, $self->packet_number);
        return $self->send_ack;
    }

    print(
        $FH $data
    ) or do {
        $self->logf(error => 'Write %s: %s', $self->file, $!);
        $self->send_error('illegal_operation');
        return 0;
    };

    $self->inc_packet_number;
    #$self->logf(trace => 'Received packet n=%i', $n);

    if(length $data < MIN_BLKSIZE) {
        $self->logf(debug => 'Peer has successfully sent %s', $self->file);
        $self->send_ack;
        return -1;
    }

    return $self->send_ack;
}

=head2 send_ack

This method is called inside L</receive_packet()> and is used to tell
the peer that a packet is received.

=cut

sub send_ack {
    my $self = shift;
    my $n = $self->packet_number - 1;

    $self->socket->send(
        pack('nna*', OPCODE_ACK, $n, ''),
        MSG_DONTWAIT,
        $self->peername,
    ) or do {
        $self->logf(error => 'Send %s: %s', $self->file, $!);
        return 0;
    };

    #$self->logf(trace => 'Sent ack n=%i', $n);

    return 1;
}

=head2 send_error

Takes a "name" indicating a type of error, which is looked up from the
C<%ERROR_CODES> variable (see the source for details). Falls back to
"not_defined", if an invalid name was passed on. Packs the data from
C<%ERROR_CODES> and pass it to the remote client. Returns 1 on success
and 1 on failure.

=cut

sub send_error {
    my $self = shift;
    my $name = shift || q();
    my $ERROR = $ERROR_CODES{$name} || $ERROR_CODES{'not_defined'};

    $self->socket->send(
        pack('nnZ*', OPCODE_ERROR, @$ERROR),
        MSG_DONTWAIT,
        $self->peername,
    ) or do {
        $self->logf(error => 'Send error=%s: %s', $name, $!);
        return 0;
    };

    return 1;
}

=head2 logf

 $self->logf($connection_obj, @message);

Receives internal log messages and (maybe) a connection object.
Is meant to be overriden when subclassing this module.

=cut

sub logf {
    my $self = shift;
    my $level = shift;
    my $format = shift;

    if($AnyEvent::TFTPd::DEBUG) {
        printf STDERR "%s %s:%s $level> $format\n",
            time,
            $self->address,
            $self->port,
            @_,
    }

    return 1;
}

=head1 BUGS

=head1 COPYRIGHT & LICENSE

=head1 AUTHOR

See L<Top::Module>.

=cut

1;
