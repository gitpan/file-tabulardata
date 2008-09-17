# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Writers::XML;

use strict;
use warnings;

use base 'File::TabularData::Writers::Base';

use MKDoc::XML::Encode;


sub new {
    my ($class, %args) = @_;
    my $self = File::TabularData::Writers::Base->new(%args);
    return bless($self, $class);
}


sub generate_header {
    my ($self, $header) = @_;
    return '<?xml version="1.0" encoding="UTF-8"?>' . "\n<xml><body><table><tr>" . join('', map { "<th>" . MKDoc::XML::Encode->process($_) . "</th>" } @$header) . "</tr>\n";
}


sub generate_footer {
    return "</table></body></xml>";
}


sub generate_row {
    my ($self, $header, $line) = @_;
    return "<tr>" . join('',
        map { "<td>" . MKDoc::XML::Encode->process($_) . "</td>" } @{[
            map {
                defined $line->{$_} ? $line->{$_} : ''
            } @$header
        ]}
    ) . "</tr>\n";
}


1;
