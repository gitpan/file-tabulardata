#!/usr/local/bin/perl

# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

TestReader->runtests;
exit;


package TestReader;

use utf8;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Temp 'tempfile';
use IO::File;
use IO::String;
use Test::More 'no_plan';
use Test::Exception;
use base qw(Test::Class);

use File::TabularData::Reader;
use File::TabularData::Utils 'catch_warnings';
use Params::Validate ":all";



##################################################
#                                                #
# Utility functions                              #
#                                                #
##################################################

sub _setup_test_fh {
    my $testdata = shift;

    ###Some test data
    $testdata ||= qq{col1\tcol2\tcol3
a\tb\tc
d\te\tf
};

    ###Make a test filehandle in memory
    my $tmpfile = IO::String->new;
    print $tmpfile $testdata;
    $tmpfile->seek(0, 0);

    return $tmpfile;
}

### Create an actual test file in a temp directory and return the handle.
my $temp_filename;
sub _setup_actual_test_file {
    my $testdata = shift;

    ###Some test data
    $testdata ||= qq{col1\tcol2\tcol3
a\tb\tc
d\te\tf
    };

    ###Make a test file.
    $temp_filename = ( -e '/home/y/tmp' ? '/home/y/tmp' : '/tmp' ) . '/dlm_reader_test_file.' . $$;

    my $fh = IO::File->new( $temp_filename, '>' );
    print $fh $testdata;

    return $temp_filename;
}

### Clean up any test files we've created
END {
    unlink $temp_filename if(
        defined $temp_filename and -f $temp_filename
    );
}



##################################################
#                                                #
# Test functions                                 #
#                                                #
##################################################

sub test__tabulardatareader_dies_for_dos_unless_told_not_to : Test(1) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

    eval {
        my $reader = new File::TabularData::Reader(
            file => $tmpfile,
        );
    };
    ok($@);

    unlink $tmpfile;
}

sub test__tabulardatareader_dies_for_dos__with_line_number : Test(1) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3\r
a\tb\tc\r
});

    eval {
        my $reader = new File::TabularData::Reader(
            file => $tmpfile,
        );
    };
    ok($@ =~ /the file first\. at .* line [\d]+$/);

    unlink $tmpfile;
}

sub test__tabulardatareader_dies_for_dos : Test(1) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3\r
a\tb\tc\r
});

    eval {
        my $reader = new File::TabularData::Reader(
            file     => $tmpfile,
        );
    };
    my $err = $@;
    ok(
        $err =~ /the file first/
    );

    unlink $tmpfile;
}

sub test__tabulardatareader_works_for_utf_16_boms : Test(1) {
    my $done = 0;
    eval
    {
        my $reader;

        # little endian
        my $tmpfile = _setup_actual_test_file(qq{\xFF\xFE}.qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

        $reader = new File::TabularData::Reader(
            file => $tmpfile,
            allow_dos_format => 1,
        ); # will die on error
        undef $reader;
        unlink $tmpfile;

        # big endian
        $tmpfile = _setup_test_fh(qq{\xFE\xFF}.qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

        $reader = new File::TabularData::Reader(
            file => $tmpfile,
            allow_dos_format => 1,
        ); # will die on error
        undef $reader;

        unlink $tmpfile;
        $done = 1;
    };
    is($done, 1);
}

sub test__tabulardatareader_works_for_utf_32_boms : Test(1) {
    my $done = 0;
    eval
    {
        my $reader;

        # little endian
        my $tmpfile = _setup_test_fh(qq{\xFF\xFE\x00\x00}.qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

        $reader = new File::TabularData::Reader(
            file => $tmpfile,
            allow_dos_format => 1,
        ); # will die on error

        # big endian
        $tmpfile = _setup_test_fh(qq{\x00\x00\xFE\xFF}.qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

        $reader = new File::TabularData::Reader(
            file => $tmpfile,
            allow_dos_format => 1,
        ); # will die on error

        unlink $tmpfile;
        $done = 1;
    };
    is($done, 1);
}

# Funky test, but proves tabulardatareader cannot deal with funky BOMs,
# though it does not die either.
sub test__tabulardatareader_doesnt_work_for_crazy_boms : Test(1) {
    # Yeah, this is a bogus BOM
    my $tmpfile = _setup_test_fh(qq{\xAB\xCD}.qq{col1\tcol2\tcol3\n
a\tb\tc\n
d\te\tf\n
});

    my $reader = new File::TabularData::Reader(
        file => $tmpfile,
    );

    # the first line will be jacked up somehow...
    my $firstline = $reader->();
    ok( not (
        ( exists($firstline->{col1}) && $firstline->{col1} eq 'a' )
        &&
        ( exists($firstline->{col2}) && $firstline->{col1} eq 'b' )
        &&
        ( exists($firstline->{col3}) && $firstline->{col1} eq 'c' )
    ));

    unlink $tmpfile;
}

sub test__tabulardatareader_can_handle_dos_format_with_bom : Test(5) {
    my $tmpfile = _setup_actual_test_file(qq{\xEF\xBB\xBF}.qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        allow_dos_format => 1,
    );

    my $firstline;
    my $warnings = catch_warnings {
        $firstline = $handle->();
    };
    ok($warnings =~ /DOS carriage returns in file/);
    is_deeply($firstline, { col1 => 'a', col2 => 'b', col3 => 'c' });

    my $secondline = $handle->();
    is_deeply($secondline, { col1 => 'd', col2 => 'e', col3 => 'f' });

    ### Only two lines ni file, so subsequent reads should produce undef
    is($handle->(), undef);
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__tabulardatareader_can_handle_dos_format : Test(5) {
    my $tmpfile = _setup_actual_test_file(qq{col1\tcol2\tcol3\r
a\tb\tc\r
d\te\tf\r
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        allow_dos_format => 1,
    );

    my $firstline;
    my $warnings = catch_warnings(
        sub {
            $firstline = $handle->();
        }
    );
    ok($warnings =~ /DOS carriage returns in file/);
    is_deeply($firstline, { col1 => 'a', col2 => 'b', col3 => 'c' });

    my $secondline = $handle->();
    is_deeply($secondline, { col1 => 'd', col2 => 'e', col3 => 'f' });

    ### Only two lines ni file, so subsequent reads should produce undef
    is($handle->(), undef);
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__read_as_coderef : Test(3) {
    my $tmpfile = _setup_test_fh();

    my $reader = new File::TabularData::Reader(file => $tmpfile);
    my $firstline = $reader->();
    is_deeply($firstline, { col1 => 'a', col2 => 'b', col3 => 'c' });

    my $secondline = $reader->();

    ### Only two lines ni file, so subsequent reads should produce undef
    is($reader->(), undef);
    is($reader->(), undef);

    unlink $tmpfile;
}

sub test__iterate : Test(4) {
    my $tmpfile = _setup_test_fh();

    my $handle = new File::TabularData::Reader(file => $tmpfile);
    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    # Throw away the second line.
    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    # We should get null now
    is($handle->(), undef);
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__has_required_fields : Test(3) {
    my $tmpfile = _setup_test_fh();

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => { type => SCALAR }
        },
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f'});

    unlink $tmpfile;
}

sub test__required_fields_now_dies_on_null : Test(3) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3
\tb\tc
d\t\tf
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => { type => SCALAR }
        },
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'b', col3 => 'c' });

    eval {
        my $line = $handle->();
    };
    ok($@);

    unlink $tmpfile;
}

sub test__required_fields_now_dies_on_null_even_when_first_bad_line_is_first_dos_line_too : Test(4) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3
\tb\tc
d\t\tf\r
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        allow_dos_format => 1,
        schema => {
            col2 => { type => SCALAR }
        },
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'b', col3 => 'c' });

    my $warnings = catch_warnings( sub {
        eval
        {
            my $line = $handle->();
        };
        ok($@ =~ /Required field/);
    });

    # Should have warned before it died.
    ok($warnings =~ /DOS carriage returns in file/);

    unlink $tmpfile;
}

sub test__required_fields_returns_null_as_before_even_when_first_bad_line_is_first_dos_line_too : Test(4) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3
\tb\tc
d\t\tf\r
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        allow_dos_format => 1,
        on_schema_validation_fails => 'warn',
        schema => {
            col2 => { type => SCALAR }
        },
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'b', col3 => 'c' });

    # Should produce two warnings:
    # DOS carriage returns, and missing required field.

    # Would use Assert->warns, but it only handles one warning at a time
    # (for now).  Refactor this when the new dts testing packages is released.
    my $warnings = catch_warnings {
        $hashref = $handle->()
    };

    ok($warnings =~ /DOS carriage returns in file.+Required field not found/isg);
    is($hashref, undef);

    unlink $tmpfile;
}

sub test__required_fields_returns_null_as_before_if_told_to : Test(4) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3
\tb\tc
d\t\tf
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => { type => SCALAR }
        },
        on_schema_validation_fails => 'warn',
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'b', col3 => 'c' });

    # This one should warn and return undef
    my $warnings = catch_warnings {
        $hashref = $handle->();
    };
    ok($warnings =~ /Required field not found in line/);

    is($hashref, undef);

    unlink $tmpfile;
}

sub test__required_fields_skips_lines_if_told_to : Test(4) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\tcol3
\tb\tc
d\t\tf
\th\ti
j\tk\tl
});

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => { type => SCALAR }
        },
        on_schema_validation_fails => 'none',
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => undef, col2 => 'h', col3 => 'i' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'j', col2 => 'k', col3 => 'l' });

    unlink $tmpfile;
}

sub test__missing_required_header : Test(1) {
    local $SIG{__WARN__} = sub { };

    my $tmpfile = _setup_test_fh();

    eval {
        my $handle = new File::TabularData::Reader(
            file => $tmpfile,
            schema => {
                col9 => { type => SCALAR }
            },
        );
    };
    ok($@);

    unlink $tmpfile;
}

sub test__allow_unknown_headers : Test(1) {
    local $SIG{__WARN__} = sub { };

    my $tmpfile = _setup_test_fh();

    eval {
        my $handle = new File::TabularData::Reader(
            file => $tmpfile,
            schema => {
                col9 => 1,
            },
            allow_unknown_headers => 1,
        );
    };
    ok($@);

    unlink $tmpfile;
}

sub test__missing_required_data : Test(3) {
    local $SIG{__WARN__} = sub { };

    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\t\tf
    };

    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => { type=> SCALAR },
        },
        on_schema_validation_fails => 'none',
    );
    ok($handle);

    # first line should be okay
    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    # second line should fail
    $hashref = $handle->();
    is($hashref, undef);

    unlink $tmpfile;
}

sub test__missing_required_headers_in_data_is_a_ok : Test(3) {
    local $SIG{__WARN__} = sub { };

    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\t\tf
    };

    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col2 => 1,
        },
    );
    ok($handle);

    # first line should be okay
    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    # second line NOT should fail
    $hashref = $handle->();
    ok($hashref);

    unlink $tmpfile;
}

sub test__has_only_these_headers : Test(3) {
    my $tmpfile = _setup_test_fh();

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col1 => 0,
            col2 => 0,
            col3 => 0,
        },
        allow_unknown_headers => 0,
    );
    ok($handle);

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    #Throw away the second line.
    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    unlink $tmpfile;
}

sub test__does_not_have_only_these_headers : Test(1) {
    local $SIG{__WARN__} = sub { }; # kill warns in tabulardatareader

    my $tmpfile = _setup_test_fh();

    eval {
        my $handle = new File::TabularData::Reader(
            file => $tmpfile,
            schema => {
                col2 => 0,
                col3 => 0,
            },
            allow_unknown_headers => 0,
        )
    };
    ok($@);

    unlink $tmpfile;
}

sub test__close_method_works : Test(1) {
    # Need an actual test file, 'cause an in-memory file won't
    # produce the below warning.
    my $tmpfile = _setup_actual_test_file();

    my $reader_obj = File::TabularData::Reader->new( file => $tmpfile );
    $reader_obj->close();

    my $warnings = catch_warnings {
        $reader_obj->();
    };
    ok($warnings =~ /readline\(\) on closed filehandle/);

    unlink $tmpfile;
}

sub test__guess_style : Test(5) {
    my $testdata = qq{col1,col2,col3
a,b,c
d,e,f
};
    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        schema => {
            col1 => 0,
            col2 => 0,
            col3 => 0,
        },
        allow_unknown_headers => 0,
        strip_enclosing_quotes => 'all',
    );

    my $hashref = $handle->();
    is($handle->style, 'csv');
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    # We should get null now
    is($handle->(), undef);

    # And still.
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__guess_style2 : Test(5) {
    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\te\tf
    };
    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
    );

    is($handle->style, 'tsv');

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    #We should get null now
    is($handle->(), undef);

    #And still.
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__iterate_csv : Test(4) {
    my $testdata = qq{col1,col2,col3
a,b,c
d,e,f
    };
    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        strip_enclosing_quotes => 'all',
        style => 'csv',
    );

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    # We should get null now
    is($handle->(), undef);

    # And still.
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__iterate_csv_complex : Test(4) {
    my $testdata = qq{col1,col2,col3
"""first"" column, first row",b,"last column's comma, comma"
d,"I'm but a poor ""middle"" column",f
    };
    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        style => 'csv',
    );

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => '"first" column, first row', col2 => 'b', col3 => 'last column\'s comma, comma' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'I\'m but a poor "middle" column', col3 => 'f' });

    #We should get null now
    is($handle->(), undef);

    #And still.
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__iterate_pipe_delim : Test(5) {
    # stick a tab in the data for fun
    my $testdata = qq{col1|col2|col3
a|b\tb|c
d|e|f
    };
    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        delimiter => '|',
    );

    is($handle->style, 'other_delimited');

    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => "b\tb", col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'e', col3 => 'f' });

    #We should get null now
    is($handle->(), undef);

    #And still.
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__slurp : Test(3) {
    my $tmpfile = _setup_test_fh(qq{col1\tcol2\n
1\t2\n
3\t4\n
});

    my @stuff = File::TabularData::Reader->new(
        file => $tmpfile,
    )->slurp;

    is(int(@stuff), 2);
    is_deeply($stuff[0], {col1 => 1, col2 => 2});
    is_deeply($stuff[1], {col1 => 3, col2 => 4});

    unlink $tmpfile;
}

sub test__strip_enclosed_quotes : Test(7) {
    local $SIG{__WARN__} = sub { };

    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\t"this is a quoted field"\tf
g\t"this is not fully quoted\ti
j\t"this has "internal" quotes"\tl
m\t\to
    };

    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        strip_enclosing_quotes => [qw/col2/]
    );
    ok($handle);

    # first line should be okay
    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'this is a quoted field', col3 => 'f' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'g', col2 => '"this is not fully quoted', col3 => 'i' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'j', col2 => 'this has "internal" quotes', col3 => 'l' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'm', col2 => undef, col3 => 'o'});

    # We should get null now
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__strip_enclosed_quotes_for_all : Test(7) {
    local $SIG{__WARN__} = sub { };

    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\t"this is a quoted field"\tf
g\t"this is not fully quoted\ti
j\t"this has "internal" quotes"\tl
m\t\to
    };

    my $tmpfile = _setup_test_fh($testdata);

    my $handle = new File::TabularData::Reader(
        file => $tmpfile,
        strip_enclosing_quotes => 'all'
    );
    ok($handle);

    # first line should be okay
    my $hashref = $handle->();
    is_deeply($hashref, { col1 => 'a', col2 => 'b', col3 => 'c' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'd', col2 => 'this is a quoted field', col3 => 'f' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'g', col2 => '"this is not fully quoted', col3 => 'i' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'j', col2 => 'this has "internal" quotes', col3 => 'l' });

    $hashref = $handle->();
    is_deeply($hashref, { col1 => 'm', col2 => undef, col3 => 'o' });

    #We should get null now
    is($handle->(), undef);

    unlink $tmpfile;
}

sub test__read_cvs_with_utf8 : Test(1) {
    my $tmpfile = _setup_test_fh(q{col1,col2
"テスト value 1",テスト value 2
});

    my $hashref = new File::TabularData::Reader(
        file => $tmpfile,
        style => 'csv',
    )->();

    is_deeply($hashref, { col1 => 'テスト value 1', col2 => 'テスト value 2' });

    unlink $tmpfile;
}

sub test__read_windows_1252_convert_to_utf8 : Test(6) {
    my $tmpfile = _setup_actual_test_file(q{URL	Tracking URL	Title	Description	Keywords
http://www.creditcards.com/credit-cards/Amazon-Platinum-Visa-Card.php	http://www.creditcards.com/credit-cards/Amazon-Platinum-Visa-Card.php?a_aid=1017&a_cid=1244	Amazon.com Platinum Visa Card	Amazon.com Platinum Visa Card at CreditCards.com featuring low apr and an online application.  Apply today with an online secure Amazon.com Platinum Visa® credit card application.	"Amazon.com Platinum Visa Card, credit card, apply, online, rate, credit card application, apr"
});

    my $handle = File::TabularData::Reader->new(
        file           => $tmpfile,
        encoding       => 'windows-1252',
        #encoding      => 'iso-8859-1', # specify encoding to open with
        allow_dos_format => 1,
    );

    while (my $line = $handle->()) {
        is( $line->{URL},            'http://www.creditcards.com/credit-cards/Amazon-Platinum-Visa-Card.php');
        is( $line->{'Tracking URL'}, 'http://www.creditcards.com/credit-cards/Amazon-Platinum-Visa-Card.php?a_aid=1017&a_cid=1244');
        is( $line->{Title},          'Amazon.com Platinum Visa Card');
        is( $line->{Description},    'Amazon.com Platinum Visa Card at CreditCards.com featuring low apr and an online application.  Apply today with an online secure Amazon.com Platinum Visa® credit card application.');
        is( $line->{Keywords},       '"Amazon.com Platinum Visa Card, credit card, apply, online, rate, credit card application, apr"');
    }

    is($handle->(), undef);
    unlink $tmpfile;
}

sub test__tabulardatareader_can_handle_xls : Test(4) {
    my $handle = new File::TabularData::Reader(
        file => "t/testdata/test.xls",
        allow_dos_format => 1,
    );

    my $firstline = $handle->();
    is_deeply($firstline, { Col1 => 'a', Col2 => 'b', Col3 => 'c' });

    my $secondline = $handle->();
    is_deeply($secondline, { Col1 => 'd', Col2 => 'e', Col3 => 'f' });

    ### Only two lines in file, so subsequent reads should produce undef
    is($handle->(), undef);
    is($handle->(), undef);
}

sub test__tabulardatareader_can_handle_zip : Test(4) {

    # Test if the reader can handle non-exist zip file.
    throws_ok{
        new File::TabularData::Reader(
            file => "t/testdata/non-exist.zip",
        )
    } qr/^Could not read zip file/;

    # Test if the reader can catch more than one data file error
    throws_ok{
        new File::TabularData::Reader(
            file => "t/testdata/test_zip.zip",
            zip_pattern => 'test_zip',
        )
    } qr/^Zip has more than one file/;

    # Test if the reader can handle with pattern
    my $handle = new File::TabularData::Reader(
            file => "t/testdata/test_zip.zip",
            zip_pattern => 'data',
    );
    my $firstline = $handle->();
    is_deeply($firstline, { Col1 => 'a', Col2 => 'b', Col3 => 'c' });
    ok( $handle->close() );
}

#sub test__tabulardatareader_can_handle_xls_xml : Test(2) {
#    eval {
#        require DTS::ExcelWriter;
#    };
#    if ($@) {
#        skip('test requires dts_public which is not installed');
#        return;
#    }
#
#    # we are going to cheat a bit and use our own ExcelWriter, since we
#    # are trying to prove that's what we can read anyway!
#
#    my ($fh, $filename) = tempfile();
#
#    my $writer = new DTS::ExcelWriter(
#        file         => $filename,
#        column_order => [ qw(foo bar quux) ],
#    );
#
#    for (my $i = 1; $i <= 69000; $i++) { # force to be more than one worksheet
#        $writer->print( {foo => $i, bar => $i, quux => 'text' } );
#    }
#    $writer->close;
#
#    # now can we read it?
#    my $handle = new File::TabularData::Reader(
#        file => $filename,
#        style => 'xls',
#    );
#
#    my ($count, $sum) = (0, 0);
#    while (my $row = $handle->()) {
#        $count++;
#        $sum += $row->{foo};
#    }
#    $handle->close();
#    unlink $filename;
#
#    is($count, 69000);
#    is($sum, 2380534500);
#}

sub test__tabulardatareader_can_handle_stdin : Test(1) {
    my $testdata = qq{col1\tcol2\tcol3
a\tb\tc
d\te\tf
    };
    my $temp_input = _setup_actual_test_file($testdata);

    my $temp_script = (-e '/home/y/tmp' ? '/home/y/tmp' : '/tmp') . '/dlm_reader_test_script.pl';
    open(SCRIPT, ">$temp_script");
    print SCRIPT "#!/usr/local/bin/perl\n";
    print SCRIPT "use File::TabularData::Reader;\n";
    print SCRIPT "my \$reader = File::TabularData::Reader->new(file => '-', allow_dos_format => 1);\n";
    print SCRIPT "while (my \$row = \$reader->()) {\n";
    print SCRIPT "    print \"\$row->{col1}\t\$row->{col2}\t\$row->{col3}\n\";\n";
    print SCRIPT "}\n";
    close(SCRIPT);

    my $temp_output = (-e '/home/y/tmp' ? '/home/y/tmp' : '/tmp') . '/dlm_reader_test.out';

    system("cat $temp_input | perl $temp_script > $temp_output");

    open(OUTPUT, "$temp_output");
    my $output = '';
    while (<OUTPUT>) {
        $output .= $_;
    }
    close(OUTPUT);

    unlink($temp_input);
    unlink($temp_script);
    unlink($temp_output);

    is($output, "a\tb\tc\nd\te\tf\n");
}
