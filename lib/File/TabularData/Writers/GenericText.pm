# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Writers::GenericText;

use strict;
use warnings;

use base 'File::TabularData::Writers::Base';


sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Writers::Base->new(%args);
    return bless($self, $class);
}


sub support_append {
    return 1;
}


sub generate_header {
    my ($self, $header) = @_;
    return join($self->{delimiter}, @$header) . "\n";
}


sub generate_footer {
}


sub generate_row {
    my ($self, $header, $line) = @_;
    return join($self->{delimiter},
        map {
            my $l = defined $line->{$_} ? $line->{$_} : '';
            $l =~ s/\n/ /g;
            $l =~ s/\r//g;
            $l;
        } @$header
    ) . "\n";
}


1;
