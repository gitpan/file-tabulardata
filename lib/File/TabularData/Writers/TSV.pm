# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Writers::TSV;

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
    return join("\t", @$header) . "\n";
}


sub generate_footer {
}


sub generate_row {
    my ($self, $header, $line) = @_;
    return join("\t",
        map {
            my $value = $line->{$_};
            $value = '' if not defined $value;
            $value =~ s/\t/    /g and warn "Got tabs in data. Replacing with four spaces.";
            $value =~ s/\n/ /g;
            $value =~ s/\r//g;
            $value;
        } @$header
    ) . "\n";
}


1;
