# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Readers::XLS;

use strict;
use warnings;

use base 'File::TabularData::Readers::Base';

use Carp;
use Memoize;
use Spreadsheet::ParseExcel;
use XML::SAX;


# Excel (XML) reading currently only suffices to read spreadsheets
# that we have output ourselves, it does not yet properly handle
# reading XML Excel files from Excel itself

sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Readers::Base->new(%args);
    $self = bless $self, $class;

    # Excel (of either binary or xml) cannot be processed from stdin
    croak "cannot process stdin for xls files" if ($self->{file} eq '-');

    # what kind is this?
    $self->{_excel_type} = _excel_type($self->{file});

    if ($self->{_excel_type} eq 'binary') {
        $self->{_xls_workbook} = Spreadsheet::ParseExcel::Workbook->Parse($self->{file});

        $self->{worksheet} = 0 unless defined $self->{worksheet};
        $self->{_xls_worksheet} = $self->{_xls_workbook}->{Worksheet}->[$self->{worksheet}];
        $self->{_headerfields} = _get_row_array($self->{_xls_worksheet}, $self->{_xls_worksheet}->{MinRow});
        my @fields = map { s/^\s*(\S.*\S)\s*$/$1/; $_; } @{$self->{_headerfields}};
        $self->{_headerfields} = \@fields;
        $self->{_xls_currentRow} = $self->{_xls_worksheet}->{MinRow} + 1;
    }
    elsif ($self->{_excel_type} eq 'xml') {
        $self->parse_xml($self->{file});
    }
    return $self;
}


sub parse_xml {
    my $self = shift;
    my $filename = shift;

    my $saxhandler = MySAXHandler->new;
    my $parser = XML::SAX::ParserFactory->parser(Handler => $saxhandler);
    $parser->parse_uri($filename);

    my $data = $saxhandler->excelData();
    $self->{_headerfields} = $data->[0];
    my @fields = map { s/^\s*(\S.*\S)\s*$/$1/; $_; } @{$self->{_headerfields}};
    $self->{_headerfields} = \@fields;
    $self->{_xls_currentRow} = 1;
    $self->{_xls_data} = $data;
}


sub _excel_type {
    my $filename = shift;

    open (FILE, '<', $filename) || croak "cannot open $filename for read: $!";
    my $line = <FILE>;
    close (FILE);
    if ($line =~ /xml.*version.*encoding/) {
        return 'xml';
    }
    else {
        return 'binary';
    }
}


sub close {
    # Spreadsheet::ParseExcel doesn't provide any 'close' method.
}


sub header_fields {
    my $self = shift;
    return $self->{_headerfields};
}


sub line_count {
    my $self = shift;
    if ($self->{_excel_type} eq 'binary') {
        my $worksheet = $self->{_xls_worksheet};
        return $worksheet->{MaxRow} - $worksheet->{MinRow} + 1;
    }
    elsif ($self->{_excel_type} eq 'xml') {
        return scalar @{$self->{_xls_data}};
    }
}


sub get_row_hash {
    my $self = shift;

    if ($self->{_excel_type} eq 'binary') {
        my $values = _get_row_array($self->{_xls_worksheet}, $self->{_xls_currentRow});
        return undef unless defined $values;
        $self->{_xls_currentRow} = $self->{_xls_currentRow} + 1;

        # Convert empty field to undef
        foreach ( @$values ){
            $_ = undef unless $_;
        }

        my %row_hash;
        @row_hash{ @{$self->{_headerfields}} } = @$values;
                return \%row_hash;
    }
    elsif ($self->{_excel_type} eq 'xml') {
        my %row_hash;
        return undef if (! defined $self->{_xls_data}->[$self->{_xls_currentRow}]);
        my @row_values = @{ $self->{_xls_data}->[$self->{_xls_currentRow}] };

        # Convert empty field to undef
        foreach ( @row_values ){
            $_ = undef unless $_;
        }

        foreach ( @{ $self->{_headerfields} } ) {
            $row_hash{$_} = shift @row_values;
        }
        $self->{_xls_currentRow} = $self->{_xls_currentRow} + 1;
        return \%row_hash;
    }
}


sub _get_row_array {
    my ($worksheet, $row) = @_;

    return undef if ($row > $worksheet->{MaxRow});

    my ($col, $cell, @values);
    for ($col = $worksheet->{MinCol}; defined $worksheet->{MaxCol} && $col <= $worksheet->{MaxCol}; $col++)
    {
        $cell = $worksheet->{Cells}[$row][$col];
        push @values, ($cell) ? $cell->Value : '';
    }

    return \@values;

}


package MySAXHandler;

use base qw(XML::SAX::Base);
use Data::Dumper;

my $row = undef;
my $col = undef;
my $in_worksheet = undef;
my $in_data = 0;
my $skip_row = 0;
my $ignore_cells = 0;


sub start_document {
    my ($self, $doc) = @_;
    # process document start event

    $row = undef;
    $col = undef;
    $in_worksheet = undef;
    $in_data = 0;
    $skip_row = 0;
    $ignore_cells = 0;

    # nop
}


sub start_element {
    my ($self, $el) = @_;
    # process element start event
    # if it's a row, mark it as such
    if ($el->{LocalName} eq 'Row') {
        $row++   if (  defined $row);
        $row = 0 if (! defined $row);

        if ($ignore_cells && ! $skip_row) {
            # we've finished ignoring cells for a row
            $ignore_cells = 0;
        }

        if ($skip_row && ! $ignore_cells) {
            # start ignoring cells
            $ignore_cells = 1;
            $skip_row = 0;
            $row--; # this row didn't count!
        }

        # rollover the col
        $col = undef;
        return;

    }
    # and for cell
    if ($el->{LocalName} eq 'Cell') {
        return if ($ignore_cells);
        $col++   if (  defined $col);
        $col = 0 if (! defined $col);
        return;
    }

    # worksheet?
    if ($el->{LocalName} eq 'Worksheet') {

        $in_worksheet = $el->{Name};
        # we want to skip the next row, if this is the second or subsequent worksheet
        # which we define by having already read some rows
        $skip_row = 1 if (defined $row);
        return;
    }

    if ($el->{LocalName} eq 'Data') {
        $in_data++;
        return;
    }
}


sub end_element {
    my ($self, $el) = @_;

    if ($el->{LocalName} eq 'Data') {
        $in_data--;
        return;
    }

    # worksheet?
    if ($el->{LocalName} eq 'Worksheet') {

        $in_worksheet = undef;
        return;
    }
}


sub characters {
   my ($self, $char) = @_;

   # ignore all data until we are in a worksheet
   return unless ($in_worksheet);

   # and in 'data'
   return unless ($in_data);

   # and ignoring cells at the moment
   return if ($ignore_cells);
   # store it
   $self->{_data}->[$row]->[$col] = $char->{Data} if (defined $char->{Data});
   $self->{_data}->[$row]->[$col] = ''            if (! defined $char->{Data});
}


sub excelData {
    my $self = shift;
    return $self->{_data};
}


1;
