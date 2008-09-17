# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Readers::CSV;

use strict;
use warnings;

use base 'File::TabularData::Readers::GenericText';

use Encode 'decode';
use Text::CSV_XS;


my $csv_parser;


sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Readers::GenericText->new(%args);
    return bless($self, $class);
}


sub parse_line {
    my ($self, $line) = @_;

    # Don't know if instantiation of parser is costly; instantiate once to be safe.
    # Set 'binary => 1' so it doesn't die on utf8 data
    $csv_parser ||= Text::CSV_XS->new({binary => 1});

    my $status = $csv_parser->parse($line);
    die "Error parsing CSV file: " . $csv_parser->error_input() . ( $self->{clean_die} ? "\n" : '' ) unless ($status);
    return [ map { decode('utf8', $_) } $csv_parser->fields() ];
}


1;
