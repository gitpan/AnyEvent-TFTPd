package AnyEvent::TFTPd::CheckConnections;

=head1 NAME

AnyEvent::TFTPd::CheckConnections - Role for AnyEvent::TFTPd for timeout checking

=head1 DESCRIPTION

This L<Moose> role can be applied to L<AnyEvent::TFTPd> which again will
provide an L<AnyEvent> timer to check for timed out connections.
See also L<MooseX::Traits> for ways to construct this object with this
role applied.

=head1 SYNOPSIS

 use AnyEvent::TFTPd;
 use AnyEvent::TFTPd::CheckConnections;

 my $tftpd = AnyEvent::TFTPd->new(...);

 # apply to all instances of AnyEvent::TFTPd
 AnyEvent::TFTPd::CheckConnections->meta->apply(AnyEvent::TFTPd->meta);

 # apply only two this instance
 AnyEvent::TFTPd::CheckConnections->meta->apply($tftpd);

 $tftpd->setup(timeout => 10); # unless set in constructor

=cut

use AnyEvent;
use Moose::Role;

#requires qw/ setup logf /;

=head1 ATTRIBUTES

=head2 timeout

Holds the timeout set in either constructor or when calling L</setup()>.

=cut

has timeout => (
    is => 'ro',
    isa => 'Int',
    writer => '_set_timeout',
    lazy_build => 1,
);

sub _build_timeout { 3 }

has _check_connection_timer => (
    is => 'ro',
    isa => 'Object',
    lazy_build => 1,
);

sub _build__check_connection_timer {
    my $self = shift;

    AnyEvent->timer(
        after => $self->timeout,
        interval => $self->timeout,
        cb => sub { $self->check_connections },
    );
}

=head1 METHODS

=head2 after setup

This method modifier will start the timed event which calls
L</check_connections()>.

=cut

after setup => sub {
    my $self = shift;
    my %args = @_;

    if(exists $args{'timeout'}) {
        $self->_set_timeout($args{'timeout'});
    }

    $self->_check_connection_timer;
};

=head2 check_connections

Will loop through all connections to see if any has timed out. If so,
decrease the number of retries and retry sending the data to peer if any
retries are possible. If not, remove the connection.

It is very important that the L<AnyEvent::TFTPd> object does not have
too many connections, since it will cause this loop to stall the program.
When that is said, the number of connections will probably cause problems
to the rest of the program, before slowing down this method.

=cut

sub check_connections {
    my $self = shift;
    my $time = time - $self->timeout;
    my $n = 0;

    for my $connection ($self->get_all_connections) {
        my $timeout = 0;

        if($connection->last_seen_peer <= $time) {
            $timeout = 1;
            $connection->dec_retries;
        }

        if($connection->retries < 0) {
            $connection->logf(error => 'Retries has exceeded');
            $self->delete_connection($connection);
            $n++;
        }
        elsif($timeout) {
            $connection->logf(error => 'Timeout has exceeded');

            if($connection->opcode == &AnyEvent::TFTPd::OPCODE_RRQ) {
                $connection->send_packet;
            }
            elsif($connection->opcode == &AnyEvent::TFTPd::OPCODE_WRQ) {
                $connection->send_ack;
            }
        }
    }

    return $n;
}

=head1 BUGS

=head1 COPYRIGHT & LICENSE

=head1 AUTHOR

See L<AnyEvent::TFTPd>.

=cut

1;
