package AnyEvent::TFTPd;

=head1 NAME

AnyEvent::TFTPd - Trivial File Transfer Protocol daemon

=head1 VERSION

0.1303

=head1 DESCRIPTION

I suddenly decided to leave any L<AnyEvent> code (including
L<AnyEvent::Handle::UDP>), due to a community and development model
that is indeed very hard to work with. If you want this module, please
drop me mail and I'll hand over the maintenance.

Update: L<AnyEvent::Handle> states:

    # too many clueless people try to use udp and similar sockets
    # with AnyEvent::Handle, do them a favour.

So instead of hacking the source of AnyEvent I'm simply abandoning this
ship.

This module handles TFTP request in an L<AnyEvent> environment. It
will set up a socket, handled by L<AnyEvent::Handle::UDP>. Every time
a new packet has arrived, it will call L</on_read()> which handles
the request. The rest is up to the L<AnyEvent::TFTPd::Connection>
object, which is possible to customize either by subclassing or
modifying with L<Moose>.

Want timeout mechanism? See L<AnyEvent::TFTPd::CheckConnections>.

=head1 SYNOPSIS

 package My::AnyEvent::Connection;
 use Moose;
 extends 'AnyEvent::TFTPd::Connection';

 sub _build_filehandle {
    my $self = shift;
    my $file = $self->file;

    # ...

    return $filehandle;
 }

 package main;

 my $tftpd = AnyEvent::TFTPd->new(
                 address => 'localhost',
                 port => 69,
                 connection_class => 'My::AnyEvent::Connection',
                 max_connections => 100,
             )->setup or die $@;

=cut

use Moose;
use AnyEvent::Handle::UDP;
use AnyEvent::TFTPd::Connection;
use IO::Socket::INET;

use constant OPCODE_RRQ => 1;
use constant OPCODE_WRQ => 2;
use constant OPCODE_DATA => 3;
use constant OPCODE_ACK => 4;
use constant OPCODE_ERROR => 5;
use constant OPCODE_OACK => 6;

our $VERSION = eval '0.1303';
our $DEBUG = 0;

=head1 ATTRIBUTES

=head2 address

Holds the address this server should bind to. Default is "127.0.0.1".

=cut

has address => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

sub _build_address { '127.0.0.1' }

=head2 port

Holds the default port this server should listen to. Default is 69.

=cut

has port => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

sub _build_port { 69 }

=head2 retries

This value will never be changes. It is used as default for the
L<AnyEvent::TFTPd::Connection::retries> attribute.

Default number of retries are 3. (default value is subject for change)

=cut

has retries => (
    is => 'ro',
    isa => 'Int',
    lazy_build => 1,
);

sub _build_retries { 3 }

=head2 connection_class

This string holds the classname where the connection objects should
be constructed from. The default L<AnyEvent::TFTPd::Connection> class
is quite useless without subclassing it. See L</SYNOPSIS> for more details.

=cut

has connection_class => (
    is => 'ro',
    isa => 'Str',
    default => 'AnyEvent::TFTPd::Connection',
);

=head2 max_connections

The max concurrent connections this object can handle. Used inside
L</on_connect()> to decide if a new connection should be establised or
not.

Setting this to zero (the default) means that the server should handle
unlimited connections.

=cut

has max_connections => (
    is => 'ro',
    isa => 'Int',
    lazy_build => 1,
);

sub _build_max_connections { 0 }

=head2 _connections

 $connection_obj = $self->get_connection(peername);
 $connection_obj = $self->add_connection($connection_obj);
 @connections = $self->get_all_connections;

This attribute holds a hash-ref, where the keys are C<peername()> of the
connections, and the values point to L<AnyEvent::TFTPd::Connection> objects.
Use the delegated methods listed above to access this attribute.

=cut

has _connections => (
    is => 'ro',
    isa => 'HashRef',
    traits => ['Hash'],
    default => sub { {} },
    handles => {
        get_connection => 'get',
        get_all_connections => 'values',
        delete_connection => 'delete',
    },
);

__PACKAGE__->meta->add_method(_clear_connections => sub {
    %{ $_[0]->_connections } = ();
});
__PACKAGE__->meta->add_method(add_connection => sub {
    return $_[0]->_connections->{"$_[1]"} = $_[1];
});

=head2 _handle

 $io_socket_inet = $self->socket;
 $packed = $self->peername;

This attribute holds an instance of L<AnyEvent::Handle::UDP>, which
handles the methods listed above.

=cut

has _handle => (
    is => 'ro',
    isa => 'AnyEvent::Handle::UDP',
    lazy_build => 1,
    handles => [qw/ socket peername /],
);

sub _build__handle {
    my $self = shift;
    
    return AnyEvent::Handle::UDP->new(
        listen => join(':', $self->address, $self->port),
        read_size => 1428, # or 512?
        on_error => sub { $self->on_error(@_) },
        on_read => sub { $self->on_read(@_) },
    );
}

=head1 METHODS

=head2 setup

This method will prepare the handle/socket for incoming connections.
It will return c<$self> on success and 0 on failure. Check C<$@> for
a full error message on failure.

Return value C<$self> allows you to chain C<new()> and C<setup()>.

=cut

sub setup {
    my $self = shift;
    my %args = @_; # used in CheckConnections

    eval {
        $self->_handle;
    } or do {
        return 0;
    };

    return $self;
}

=head2 on_read

This hook is called each time data is received from a peer host.
It will parse the datagram received and act accordingly.

=cut

sub on_read {
    my $self = shift;
    my $handle = shift;
    my $datagram = $handle->rbuf;
    my $opcode = unpack 'n', substr $datagram, 0, 2, '';
    my $connection;

    $handle->{'rbuf'} = ''; # clear buffer

    # ===============
    # Init connection

    if($opcode == OPCODE_RRQ) {
        if($connection = $self->on_connect($opcode, $datagram)) {
            $connection->send_packet;
            return 1;
        }
        return 0;
    }
    elsif($opcode == OPCODE_WRQ) {
        if($connection = $self->on_connect($opcode, $datagram)) {
            $connection->send_ack;
            return 1;
        }
        return 0;
    }

    # ======================
    # Connection in progress

    $connection = $self->get_connection($handle->peername);

    if(!$connection) {
        $connection = $self->connection_class->new(
                          opcode => $opcode,
                          peername => $handle->peername,
                          server => $self,
                      );

        $connection->logf(warn => 'Connection is not established');
        $connection->send_error('no_connection');

        return 0;
    }

    if($opcode == OPCODE_ACK) {
        if($connection->receive_ack($datagram) == -1) {
            $self->delete_connection($connection);
            return -1;
        }
    }
    elsif($opcode == OPCODE_DATA) {
        if($connection->receive_packet($datagram) == -1) {
            $self->delete_connection($connection);
            return -1;
        }
    }
    elsif($opcode == OPCODE_ERROR) {
        my($code, $msg) = unpack 'nZ*', $datagram;
        $connection->logf(error => 'Error from client: %s/%s', $code, $msg);
    }
    else {
        $connection->logf(error => 'Unknown opcode: %i', $opcode);
        $connection->send_error('unknown_opcode');
        return 0;
    }

    if($connection->retries == -1) {
        $connection->logf(error => 'Retries has exceeded');
        $self->delete_connection($connection);
        return 0;
    }

    return 1;
}

=head2 on_connect

This method returns a new L<AnyEvent::TFTPd::Connection> object for
a new connection. This method is called when either a RRQ/WRQ opcode
is received in L</on_read()>.

This method might skip these steps if no more connections are
available. This is computed by comparing the number of connections
and L</max_connections>.

=cut

sub on_connect {
    my $self = shift;
    my $opcode = shift;
    my $datagram = shift;
    my $max_connections = $self->max_connections;
    my($file, $mode, @rfc) = split "\0", $datagram;
    my $connection;

    $connection = $self->connection_class->new(
                      opcode => $opcode,
                      peername => $self->peername,
                      server => $self,
                      file => $file,
                      mode => lc($mode),
                      rfc => \@rfc,
                  );

    if(0 < $max_connections and $max_connections <= $self->get_all_connections) {
        $connection->logf(debug => 'Max connection limit reached');
        return;
    }
    else {
        $connection->logf(debug => 'Connection established');
        return $self->add_connection($connection);
    }
}

=head2 on_error

This hook is called from the handler, when something unexpected has
happened. See L<AnyEvent::Handle> for details.

=cut

sub on_error {
    my $self = shift;
    my $handle = shift;
    my $fatal = shift;
    my $message = shift;

    warn $message if $DEBUG;

    if($fatal) {
        # rebuild handle
        $self->_clear_connections;
        $self->_clear_handle;
        $self->_handle;
    }

    return 1;
}

=head1 COPYRIGHT & LICENSE

Copyright 2007 Jan Henning Thorsen, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Jan Henning Thorsen C<< jhthorsen at cpan.org >>

=cut

1;
