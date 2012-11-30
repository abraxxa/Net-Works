package Net::Works::Address;

use strict;
use warnings;

use Carp qw( confess );
use Data::Validate::IP qw(is_ipv4);
use Math::BigInt try => 'GMP';
use NetAddr::IP::Util qw( inet_any2n bin2bcd bcd2bin ipv6_n2x );
use Scalar::Util qw( blessed );
use Socket qw(AF_INET AF_INET6 inet_pton inet_ntop);

# Using this currently breaks overloading - see
# https://rt.cpan.org/Ticket/Display.html?id=50938
#
#use namespace::autoclean;

use overload (
    q{""} => 'as_string',
    '<=>' => '_compare_overload',
);

use Moose;

has _as_integer => (
    is => 'ro',

    #    isa      => 'Int',
    required => 1,
);

has version => (
    is => 'ro',

    #isa => 'Int',
    required => 1,
);

# FIX - should be shared
sub _string_to_integer {
    my $address = shift;

    if ( is_ipv4($address) ) {
        return unpack 'N', inet_pton( AF_INET, $address );
    }
    else {
        return Math::BigInt->new(
            bin2bcd( inet_pton( AF_INET6, $address ) ) );
    }
}

sub new_from_string {
    my $class = shift;
    my %p     = @_;

    my $str = delete $p{string};
    my $int = _string_to_integer($str);

    my $version = delete $p{version};
    $version ||= is_ipv4($str) ? 4 : 6;

    return $class->new( _as_integer => $int, version => $version, %p );
}

sub new_from_integer {
    my $class = shift;
    my %p     = @_;

    my $int     = delete $p{integer};
    my $version = delete $p{version};
    $version ||= ref $int ? 6 : 4;

    $int = Math::BigInt->new($int) if $version == 6;

    return $class->new( _as_integer => $int, version => $version, %p );
}

sub as_string {
    my $self = shift;

    return $self->version() == 6
        ? inet_ntop AF_INET6, bcd2bin( $self->_as_integer )
        : inet_ntop AF_INET, pack( 'N', $self->_as_integer );
}

sub as_integer {
    my $self = shift;

    return $self->_as_integer;
}

sub as_binary {
    my $self = shift;

    return inet_any2n( $self->as_string );
}

sub as_ipv4_string {
    my $self = shift;

    return $self->as_string() if $self->version() == 4;

    confess
        'Cannot represent IP address larger than 2**32-1 as an IPv4 string'
        if $self->as_integer() >= 2**32;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer(),
        version => 4,
    )->as_string();
}

sub as_bit_string {
    my $self = shift;

    if ( $self->version == 6 ) {
        my $bin = $self->as_integer->as_bin();

        $bin =~ s/^0b//;
        return sprintf( '%0128s', $bin );
    }
    else {
        return sprintf( '%032b', $self->as_integer );
    }
}

sub mask_length { $_[0]->version == 6 ? 128 : 32 }

sub next_ip {
    my $self = shift;

    my $bits = $self->mask_length();
    confess "$self is the last address in its range"
        if $self->as_integer() == do { use bigint; ( 2**$bits - 1 ) };

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer() + 1,
        version => $self->version()
    );
}

sub previous_ip {
    my $self = shift;

    confess "$self is the first address in its range"
        if $self->as_integer() == 0;

    return __PACKAGE__->new_from_integer(
        integer => $self->as_integer() - 1,
        version => $self->version(),
    );
}

sub _compare_overload {
    my $self  = shift;
    my $other = shift;
    my $flip  = shift() ? -1 : 1;

    confess 'Cannot compare unless both objects are '
        . __PACKAGE__
        . ' objects'
        unless blessed $self
        && blessed $other
        && eval { $self->isa(__PACKAGE__) && $other->isa(__PACKAGE__) };

    return $flip * ( $self->as_integer() <=> $other->as_integer() );
}

__PACKAGE__->meta()->make_immutable();

1;

# ABSTRACT: An object representing a single IP (4 or 6) address

__END__

=head1 SYNOPSIS

  my $ip = Net::Works::Address->new( address => '1.2.3.4' );
  print $ip->as_string();     # 1.2.3.4
  print $ip->as_integer();    # 16909060
  print $ip->as_binary();     # 4-byte packed form of the address
  print $ip->as_bit_string(); # 00000001000000100000001100000100
  print $ip->version();       # 4
  print $ip->mask_length();   # 32

  my $next = $ip->next_ip();     # 1.2.3.5
  my $prev = $ip->previous_ip(); # 1.2.3.4

  if ( $next > $ip ) { ... }

  my @sorted = sort $next, $prev, $ip;

  my $ip = Net::Works::Address->new( address => 'a900::1234' );
  print $ip->as_integer(); # 224639531287650782520743393187378238004

  my $ip = Net::Works::Address->new_from_integer( integer => 16909060 );

=head1 DESCRIPTION

Objects of this class represent a single IP address. It can handle both IPv4
and IPv6 addresses. It provides various methods for getting information about
the address, and also overloads the objects so that addresses can be compared
as integers.

For IPv6, it uses big integers (via Math::BigInt) to represent the numeric
value of an address.

This module is currently a thin wrapper around NetAddr::IP but that could
change in the future.

=head1 METHODS

This class provides the following methods:

=head2 Net::Works::Address->new_from_string( ... )

This method takes a C<string> parameter and an optional C<version>
parameter. The C<string> parameter should be a string representation of an IP
address.

The C<version> parameter should be either C<4> or C<6>, but you don't really need
this unless you're trying to force a dotted quad to be interpreted as an IPv6
address or to a force an IPv6 address colon-separated hex number to be
interpreted as an IPv4 address.

=head2 Net::Works::Address->new_from_integer( ... )

This method takes a C<integer> parameter and an optional C<version>
parameter. The C<integer> parameter should be an integer representation of an
IP address.

The C<version> parameter should be either C<4> or C<6>. Unlike with strings,
you'll need to set the version explicitly to get an IPv6 address.

=head2 $ip->as_string()

Returns a string representation of the address like "1.2.3.4" or
"ffff::a:1234".

=head2 $ip->as_integer()

Returns the address as an integer. For IPv6 addresses, this is returned as a
L<Math::BigInt> object, regardless of the value.

=head2 $ip->as_binary()

Returns the packed binary form of the address (4 or 16 bytes).

=head2 $ip->as_bit_string()

Returns the address as a string of 1's and 0's, like
"00000000000000000000000000010000".

=head2 $ip->as_ipv4_string()

This returns a dotted quad representation of an address, even if it's an IPv6
address. However, this will die if the address is greater than the max value
of an IPv4 address (2**32 - 1). It's primarily useful for debugging.

=head2 $ip->version()

Returns a 4 or 6 to indicate whether this is an IPv4 or IPv6 address.

=head2 $ip->mask_length()

Returns the mask length for the IP address, which is either 32 (IPv4) or 128
(IPv6).

=head2 $ip->next_ip()

Returns the numerically next IP, regardless of whether or not it's in the same
subnet as the current IP.

This will throw an error if the current IP address it the last address in its
IP range.

=head2 $ip->previous_ip()

Returns the numerically previous IP, regardless of whether or not it's in the
same subnet as the current IP.

This will throw an error if the current IP address it the first address in
its IP range (address 0).

=head1 OVERLOADING

This class overloads numeric comparison, allowing you to compare two objects
numerically and to sort them.

It also overloads stringification to call the C<< $ip->as_string() >> method.
