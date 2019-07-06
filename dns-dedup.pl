#!/usr/bin/perl
# -*- coding: utf-8 -*-

package dns_dedup_main;

use strict;
use warnings;
use feature qw( say );

use Getopt::Long qw(:config posix_default bundling no_ignore_case );
use File::Basename qw ( basename );

our $VERSION = "0.1";
our $NAME    = "dns-dedup";
our $DESC    = "deduplicate domain name lists";

my $prog_name   = basename($0);
my $short_usage = "${prog_name} {-c <N>|-h|-o <FILE>|-U <ZTYPE>} [<FILE>...]";
my $usage       = <<'EOF';
${NAME} (${VERSION}) - ${DESC}

Usage:
  ${short_usage}

Options:
  -C, --autocollapse <N>    reduce input domain names to depth <N>
  -h, --help                print this help message and exit
  -o, --outfile <FILE>      write output to <FILE> instead of stdout
  -U, --unbound [<ZTYPE>]   write output in unbound.conf(5) local-zone format
                            ZTYPE may be used to set the zone type,
                            it defaults to \"always_nxdomain\".
                            (convenience helper)

Positional Arguments:
  FILE...                   read domain names from files instead of stdin

Exit Codes:
    0                       success
   64                       usage error
  255                       error
EOF

our $EMPTY = q{};


# write_domains_to_fh ( outfh, domains, outformat, outformat_arg )
sub write_domains_to_fh {
    my ( $outfh, $domains_ref, $outformat, $outformat_arg ) = @_;
    my @domains = @{ $domains_ref };

    # write output file
    if ( (not defined $outformat) || ($outformat eq $EMPTY) ) {
        foreach (@domains) { say $outfh $_; }

        return 0;

    } elsif ( $outformat eq "unbound" ) {
        my $zone_type;

        if ( (not defined $outformat_arg) or ($outformat_arg eq $EMPTY) ) {
            $zone_type = "always_nxdomain";
        } else {
            $zone_type = $outformat_arg;
        }

        foreach (@domains) {
            printf $outfh "local-zone: \"%s.\" %s\n", $_, $zone_type
        }

        return 0;

    } else {
        return 1;
    }
}


# main ( **@ARGV )
sub main {
    my $ret;

    # parse args
    my $autocol_depth   = undef;
    my $want_help       = 0;
    my $outfile         = undef;
    my $outformat       = undef;
    my $outformat_arg   = undef;

    if (
        ! GetOptions (
            "C|autocollapse=i"  => \$autocol_depth,
            "h|help"            => \$want_help,
            "o|outfile=s"       => \$outfile,
            "U|unbound:s"       => sub {
                $outformat = "unbound";
                $outformat_arg = $_[1];
            }
        )
    ) {
        say STDERR "Usage: ", $short_usage;
        return 1;  # FIXME EX_USAGE
    }

    # help => exit
    if ( $want_help ) {
        # newline at end supplied by $usage
        print $usage;
        return 0;
    }

    # create DNS tree, read input files
    my $tree = DnsTree->new ( $autocol_depth );

    if ( scalar @ARGV ) {
        foreach (@ARGV) {
            open ( my $infh, "<", $_ ) or die "Failed to open input file: $!\n";
            $tree->read_fh ( $infh );
            close ( $infh ) or warn "Failed to close input file: $!\n";
        }

    } else {
        $tree->read_fh ( *STDIN );
    }

    my @domains = @{ $tree->collect() };

    # write output file
    if ( defined $outfile ) {
        my $outfh;

        open ( $outfh, ">", $outfile ) or die "Failed to open outfile: $!\n";
        $ret = write_domains_to_fh ( $outfh, \@domains, $outformat, $outformat_arg );
        close ( $outfh ) or warn "Failed to close outfile: $!\n";

    } else {
        $ret = write_domains_to_fh ( *STDOUT, \@domains, $outformat, $outformat_arg );
    }

    if ( $ret != 0 ) { die "outformat not implemented: ${outformat}\n"; }

    return 0;
}


exit(main());



# class DnsTree
#
# + DnsTree ( autocol_depth=undef )
# + DnsTreeNode insert ( str domain_name )
# + void read_fh ( fh )
# + ArrayRef<str> collect()
#
package DnsTree;

use strict;
use warnings;


sub new {
    my $class = shift;
    my $self  = {
        # auto collapse depth, may be undef for no autocol
        _acd  => shift,
        _root => DnsTreeNode->new ( q{.} )
    };

    return bless $self, $class;
}


# collect ( self )
sub collect {
    my $self = shift;
    my @dst_arr = ();

    $self->{_root}->collect ( \@dst_arr );

    return \@dst_arr;
}


# insert ( self, domain_name )
sub insert {
    my ( $self, $domain_name ) = @_;

    # lowercase -> split on "." -> ignore empty parts
    my @key_path = grep { '/./' } ( split ( /\./xm, lc $domain_name ) );

    # auto-collapse if enabled
    if ( (defined $self->{_acd}) && ($self->{_acd} >= 0) ) {
        my $excess = (scalar @key_path) - $self->{_acd};

        if ( $excess > 0 ) {
            @key_path = @key_path [ $excess .. $#key_path ];
        }
    }

    # insert
    return $self->{_root}->insert ( \@key_path );
}


# read_fh ( self, fh )
sub read_fh {
    my ( $self, $fh ) = @_;

    while (<$fh>) {
        # str_strip()
        s/^\s+//xm;
        s/\s+$//xm;

        # skip empty and comment lines
        if ( /^[^#]/xm ) {
            $self->insert ( $_ );
        }
    }

    return 0;
}


# class DnsTreeNode
#
# + DnsTreeNode insert ( ArrayRef<str> key_path )
# + void collect ( ArrayRef<str> dst_arr )
#
package DnsTreeNode;

use strict;
use warnings;


sub new {
    my $class = shift;
    my $self  = {
        _name  => shift,  # may be undef
        _hot   => 0,
        _nodes => {}
    };

    return bless $self, $class;
}


# get_child_node_name ( self, subdomain )
sub get_child_node_name {
    my ( $self, $subdomain ) = @_;

    my $name = $self->{_name};

    if ( (defined $name) && ($name ne q{}) && ($name ne q{.}) ) {
        return join ( q{.}, ( $subdomain, $name ) );
    } else {
        return $subdomain;
    }
}


# get_child_node ( subdomain )
sub get_child_node {
    my ( $self, $subdomain ) = @_;

    my $nodes = $self->{_nodes};
    my $node;

    if ( exists $nodes->{$subdomain} ) {
        $node = $nodes->{$subdomain};

    } else {
        $node = DnsTreeNode->new ( $self->get_child_node_name ( $subdomain ) );
        $nodes->{$subdomain} = $node;
    }

    return $node;
}


# insert ( self, key_path )
sub insert {
    my ( $self, $key_path ) = @_;

    my $node_key = pop @{ $key_path };

    if ( $self->{_hot} ) {
        return $self;

    } elsif ( not defined $node_key ) {
        $self->{_hot} = 1;
        return $self;

    } else {
        my $node = $self->get_child_node ( $node_key );
        return $node->insert ( $key_path );
    }
}


# collect ( self, dst_arr )
sub collect {
    my ( $self, $dst_arr ) = @_;

    if ( $self->{_hot} ) {
        push @{ $dst_arr }, $self->{_name};

    } else {
        # sort by top-level domain, then second-level domain a.s.o.
        foreach my $key ( sort ( keys %{ $self->{_nodes} } ) ) {
            $self->{_nodes}->{$key}->collect ( $dst_arr );
        }
    }

    return 0;
}
