# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Readers::Base;

use strict;
use warnings;

use Carp;


sub new {
    my ($class, %args) = @_;
    my $self = bless \%args, $class;
    return $self;
}


sub header_fields {
    die "Not implemented";
}


sub line_count {
    die "Not implemented";
}


sub get_row_hash {
    die "Not implemented";
}


sub close {
}


1;
