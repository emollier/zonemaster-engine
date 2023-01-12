package Zonemaster::Engine::Util;

use 5.014002;

use strict;
use warnings;

use version; our $VERSION = version->declare("v1.1.13");

use Exporter 'import';
BEGIN {
    our @EXPORT_OK = qw[
      info
      ipversion_ok
      name
      ns
      parse_hints
      pod_extract_for
      should_run_test
      scramble_case
      test_levels
    ];
    our %EXPORT_TAGS = ( all => \@EXPORT_OK );

    ## no critic (Modules::ProhibitAutomaticExportation)
    our @EXPORT = qw[ ns info name pod_extract_for scramble_case ];
}

use Net::DNS::ZoneFile;
use Pod::Simple::SimpleTree;

use Zonemaster::Engine;
use Zonemaster::Engine::Constants qw[:ip];
use Zonemaster::Engine::DNSName;
use Zonemaster::Engine::Profile;

## no critic (Subroutines::RequireArgUnpacking)
sub ns {
    return Zonemaster::Engine->ns( @_ );
}

sub info {
    my ( $tag, $argref ) = @_;

    return Zonemaster::Engine->logger->add( $tag, $argref );
}

sub should_run_test {
    my ( $test_name ) = @_;
    my %test_names = map { $_ => 1 } @{ Zonemaster::Engine::Profile->effective->get( q{test_cases} ) };

    return exists $test_names{$test_name};
}

sub ipversion_ok {
    my ( $version ) = @_;

    if ( $version == $IP_VERSION_4 ) {
        return Zonemaster::Engine::Profile->effective->get( q{net.ipv4} );
    }
    elsif ( $version == $IP_VERSION_6 ) {
        return Zonemaster::Engine::Profile->effective->get( q{net.ipv6} );
    }
    else {
        return;
    }
}

sub test_levels {

    return Zonemaster::Engine::Profile->effective->get( q{test_levels} );
}

sub name {
    my ( $name ) = @_;

    return Zonemaster::Engine::DNSName->new( $name );
}

# Functions for extracting POD documentation from test modules

sub _pod_process_tree {
    my ( $node, $flags ) = @_;
    my ( $name, $ahash, @subnodes ) = @{$node};
    my @res;

    $flags //= {};

    foreach my $node ( @subnodes ) {
        if ( ref( $node ) ne 'ARRAY' ) {
            $flags->{tests} = 1 if $name eq 'head1' and $node eq 'TESTS';
            if ( $name eq 'item-text' and $flags->{tests} ) {
                $node =~ s/\A(\w+).*\z/$1/x;
                $flags->{item} = $node;
                push @res, $node;
            }
        }
        else {
            if ( $flags->{item} ) {
                push @res, _pod_extract_text( $node );
            }
            else {
                push @res, _pod_process_tree( $node, $flags );
            }
        }
    }

    return @res;
} ## end sub _pod_process_tree

sub _pod_extract_text {
    my ( $node ) = @_;
    my ( $name, $ahash, @subnodes ) = @{$node};
    my $res = q{};

    foreach my $node ( @subnodes ) {
        if ( $name eq q{item-text} ) {
            $node =~ s/\A(\w+).*\z/$1/x;
        }

        if ( ref( $node ) eq q{ARRAY} ) {
            $res .= _pod_extract_text( $node );
        }
        else {
            $res .= $node;
        }
    }

    return $res;
} ## end sub _pod_extract_text

sub pod_extract_for {
    my ( $name ) = @_;

    my $parser = Pod::Simple::SimpleTree->new;
    $parser->no_whining( 1 );

    my %desc = eval { _pod_process_tree( $parser->parse_file( $INC{"Zonemaster/Engine/Test/$name.pm"} )->root ) };

    return \%desc;
}

# Function from CPAN package Text::Capitalize that causes
# issues when installing ZM.
#
sub scramble_case {
    my $string = shift;
    my ( @chars, $uppity, $newstring, $uppers, $downers );

    @chars = split //, $string;

    $uppers  = 2;
    $downers = 1;
    foreach my $c ( @chars ) {
        $uppity = int( rand( 1 + $downers / $uppers ) );

        if ( $uppity ) {
            $c = uc( $c );
            $uppers++;
        }
        else {
            $c = lc( $c );
            $downers++;
        }
    }
    $newstring = join q{}, @chars;
    return $newstring;
}    # end sub scramble_case

sub parse_hints {
    my $string = shift;

    # Reject anything that is forbidden in hints files but allowed in zone files
    # in general.
    if ( $string =~ /^\$(TTL|INCLUDE|ORIGIN|GENERATE)/m ) {
        die "Forbidden directive \$$1\n";
    }

    my $rrs = Net::DNS::ZoneFile->parse( \$string );
    if ( !defined $rrs ) {
        die "Unable to parse root hints\n";
    }

    my %ns;
    my %glue;
    for my $rr ( @$rrs ) {
        if ( $rr->class ne 'IN' ) {
            my $rrclass = $rr->class;
            die "Forbidden RR class $rrclass\n";
        }

        if ( $rr->type eq 'NS' ) {
            if ( $rr->owner ne '.' ) {
                my $owner = $rr->owner;
                die "Owner name for NS record must be \".\"\n";
            }
            $ns{ $rr->nsdname } = 0;
        }
        elsif ( $rr->type eq 'A' || $rr->type eq 'AAAA' ) {
            $glue{ $rr->owner } = $rr->type;
        }
        else {
            my $rrtype = $rr->type;
            die "Forbidden RR type $rrtype\n";
        }
    } ## end for my $rr ( @$rrs )

    for my $owner ( sort keys %glue ) {
        if ( exists $ns{$owner} ) {
            $ns{$owner} = 1;
        }
        else {
            my $rrtype = $glue{$owner};
            die "Ownername of $rrtype record does not match any NS RDATA\n";
        }
    }

    for my $nsdname ( sort keys %ns ) {
        if ( $ns{$nsdname} == 0 ) {
            die "No address record found for NS $nsdname\n";
        }
    }

    if ( !%ns ) {
        die "No NS record found\n";
    }

    # Extract hint data
    my %hints;
    for my $rr ( @{ $rrs } ) {
        if ( $rr->type eq 'A' or $rr->type eq 'AAAA' ) {
            push @{ $hints{$rr->owner} }, $rr->address;
        }
    }

    return \%hints;
}

sub serial_gt {
    my ( $sa, $sb ) = @_;

    return ( $sa > $sb and ( ($sa - $sb) < 2**(32 - 1) ) );
}

1;

=head1 NAME

Zonemaster::Engine::Util - utility functions for other Zonemaster modules

=head1 SYNOPSIS

    use Zonemaster::Engine::Util;
    info(TAG => { some => 'argument'});
    my $ns = ns($name, $address);
    my $name = name('whatever.example.org');

=head1 EXPORTED FUNCTIONS

=over

=item info($tag, $href)

Creates and returns a L<Zonemaster::Engine::Logger::Entry> object. The object
is also added to the global logger object's list of entries.

=item ns($name, $address)

Creates and returns a nameserver object with the given name and address.

=item name($string_name_or_zone)

Creates and returns a L<Zonemaster::Engine::DNSName> object for the given argument.

=item parse_hints($string)

Parses a string in the root hints format into the format expected by
Zonemaster::Engine::Resolver->add_fake_addresses().

Returns a hashref with domain names as keys and arrayrefs to IP addresses as
values.

Throws an exception if the inputs is not valid root hints text.

A root hints file is a valid RFC 1035 zone file of the same type IANA publishes
to be used as hint file for name servers
L<https://www.internic.net/domain/named.root>.

In addition to being valid zone file the following restrictions are imposed on
the root hints format:

=over

=item *
The file must not contain any $TTL, $ORIGIN, $INCLUDE or $GENERATE directives.

=item *
The class field of all records must be "IN" or absent. If class is absent, IN is
assumed.

=item *
The TTL field may be absent or present. The TTL value is ignored.

=item *
The RR type of all DNS records must be NS, A or AAAA.

=item *
The file must contain at least one NS record.

=item *
The owner name of all NS records must be C<.>.

=item *
For every NS record there must be at least one address record (A or AAAA) whose
owner name is identical to the domain name in the RDATA of the NS record.

=item *
All address records (A or AAAA) must have an owner name that is identical to the
domain name in the RDATA of some NS record in the zone.

=back

=item pod_extract_for($testname)

Will attempt to extract the POD documentation for the test methods in
the test module for which the name is given. If it can, it returns a
reference to a hash where the keys are the test method names and the
values the documentation strings.

This method blindly assumes that the structure of the POD is exactly
like that in the Basic test module.
If it's not, the results are undefined.

=item serial_gt($serial_a, $serial_b)
Checks if serial_a is greater than serial_b, according to serial number arithemtic defined in RFC1982.

Return a boolean.

=item scramble_case

This routine provides a special effect: sCraMBliNg tHe CaSe

=item should_run_test

Check if a test is blacklisted and should run or not.

=item ipversion_ok

Check if IP version operations are permitted. Tests are done against Zonemaster::Engine::Profile->effective content.

=item test_levels

WIP, here to please L<Pod::Coverage>.

=back
