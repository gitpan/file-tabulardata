# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Readers::GenericText;

use strict;
use warnings;

use base 'File::TabularData::Readers::Base';

use Carp;
use File::TabularData::Utils;


sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Readers::Base->new(%args);
    $self = bless $self, $class;

    my ($filename, $handle, $encoding) = File::TabularData::Utils::open_file($self->{file}, $self->{encoding});
    $self->{_filename} = $filename;
    $self->{_filehandle} = $handle;
    $self->{_encoding} = $encoding;
    $self->{_cr_warned} = 0;

    my $headerline = (defined $self->{_headerline}) ? $self->{_headerline} : <$handle>;
    $headerline =~ s/\r//sg
        and not $self->{allow_dos_format}
        and croak "DOS carriage returns in header. Do dos2unix on the file first.";
    chomp $headerline;
    $self->{_headerline} = $headerline;

    return $self;
}


sub header_fields {
    my $self = shift;
    return $self->{_headerfields} if $self->{_headerfields};

    $self->{_headerfields} = $self->parse_line($self->{_headerline});
    my @fields = map { s/^\s*(\S.*\S)\s*$/$1/; $_; } @{$self->{_headerfields}};
    $self->{_headerfields} = \@fields;

    return $self->{_headerfields};
}


sub get_row_hash {
    my $self = shift;
    my $filehandle = $self->{_filehandle};

    my $data = '';
    while (defined $data and $data !~ /\S/) { # Skip empty lines
        $data = <$filehandle>;
    }
    return undef unless defined $data;

    my %row_hash;

    # Use ordered hash.
    if ($self->{ordered_hashes}) {
        tie %row_hash, 'Tie::IxHash';
    }

    # De-DOS the line
    $data =~ s/\r//sg and $self->warn_cr();
    chomp $data;

    # Parse line into hash
    my $values = $self->parse_line($data);

    # Convert empty field to undef
    foreach ( @$values ){
        $_ = undef unless $_;
    }

    @row_hash{ @{ $self->header_fields() } } = @$values;

    return \%row_hash;
}


sub parse_line {
    my ($self, $line) = @_;
    return [ split($self->{delimiter}, $line) ];
}


sub warn_cr {
    my $self = shift;
    return if ((defined $self->{_cr_warned}) && ($self->{_cr_warned} == 1));
    carp "DOS carriage returns in file" unless ( $self->{_encoding} eq 'windows-1252' );
    $self->{_cr_warned} = 1;
}


sub line_count {
    my $self = shift;
    return File::TabularData::Utils::lines_in_file($self->{_filename});
}


sub close {
    my $self = shift;
    close $self->{_filehandle};
}


1;
