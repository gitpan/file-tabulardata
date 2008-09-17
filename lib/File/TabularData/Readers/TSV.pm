# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Readers::TSV;

use strict;
use warnings;

use base 'File::TabularData::Readers::GenericText';


sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Readers::GenericText->new(%args);
    return bless($self, $class);
}


sub parse_line {
    my ($self, $line) = @_;
    return [ split("\t", $line) ];
}


1;
