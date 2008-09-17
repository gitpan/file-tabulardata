#!/usr/local/bin/perl

# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

TestWriter->runtests;
exit;

package TestWriter;

use strict;
use warnings;
use utf8;

use Carp;
use Data::Dumper;
use File::BOM qw/open_bom/;
use File::Temp 'tempfile';
use IO::File;
use Params::Validate ':all';
use Test::Exception;
use Test::More;
use Tie::IxHash;

use File::TabularData::Reader;
use File::TabularData::Writer;
use File::TabularData::Utils 'catch_warnings';

use base qw(Test::Class);


sub _rewind_and_verify {
    my ($fh, $expected_content, $position, $whence) = @_;
    $position = 0 unless $position;
    $whence = 0 unless $whence;
    $fh->flush();
    seek($fh, 0, 0);
    local $/ = undef;
    my $data = <$fh>;
    is($data, $expected_content);
}


sub test_default : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh);

    $writer->write({
        key1 => 'val1',
        key2 => 'val2'
    });
    _rewind_and_verify($fh, qq{key1\tkey2\nval1\tval2\n});

    throws_ok{
        $writer->write({ unknown_key => 'blah' });
    } qr/The following key in the input hash is not listed in schema: unknown_key/;

    $writer->write({
        key1 => 'val3',
        key2 => 'val4'
    });
    _rewind_and_verify($fh, qq{key1\tkey2\nval1\tval2\nval3\tval4\n});

    $writer->close();
}


sub test_schema_in_hash_style : Test(11) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(
        file => $fh,
        schema => {
            col4 => 0,
            col1 => 1,
            col3 => { type => SCALAR },
            col2 => { optional => 1, type => SCALAR },
        }
    );

    $writer->write({
        col4 => 'val14',
        col1 => 'val11',
        col3 => 'val13',
        col2 => 'val12',
    });
    my $expected = qq{col1\tcol2\tcol3\tcol4\nval11\tval12\tval13\tval14\n};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        # col4 is missing
        col1 => 'val21',
        col3 => 'val23',
        col2 => 'val22',
    });
    $expected .= qq{val21\tval22\tval23\t\n};
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val34',
            # col1 is missing
            col3 => 'val33',
            col2 => 'val32',
        });
    } qr/'col1' missing/;
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val44',
            col1 => 'val41',
            # col3 is missing
            col2 => 'val42',
        });
    } qr/'col3' missing/;
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val54',
            col1 => 'val51',
            col3 => undef, # col3 is not SCALAR
            col2 => 'val52',
        });
    } qr/'col3'.*not one of the allowed types: scalar/;
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col4 => 'val64',
        col1 => 'val61',
        col3 => 'val63',
        # col2 is missing
    });
    $expected .= qq{val61\t\tval63\tval64\n};
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val74',
            col1 => 'val71',
            col3 => 'val74',
            col2 => undef, # col2 is not SCALAR
        });
    } qr/'col2'.*not one of the allowed types: scalar/;
    _rewind_and_verify($fh, $expected);

    $writer->close();
}


sub test_schema_in_array_style : Test(11) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(
        file => $fh,
        schema => [
            col4 => 0,
            col1 => 1,
            col3 => { type => SCALAR },
            col2 => { optional => 1, type => SCALAR },
        ]
    );

    $writer->write({
        col4 => 'val14',
        col1 => 'val11',
        col3 => 'val13',
        col2 => 'val12',
    });
    my $expected = qq{col4\tcol1\tcol3\tcol2\nval14\tval11\tval13\tval12\n};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        # col4 is missing
        col1 => 'val21',
        col3 => 'val23',
        col2 => 'val22',
    });
    $expected .= qq{\tval21\tval23\tval22\n};
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val34',
            # col1 is missing
            col3 => 'val33',
            col2 => 'val32',
        });
    } qr/'col1' missing/;
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val44',
            col1 => 'val41',
            # col3 is missing
            col2 => 'val42',
        });
    } qr/'col3' missing/;
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val54',
            col1 => 'val51',
            col3 => undef, # col3 is not SCALAR
            col2 => 'val52',
        });
    } qr/'col3'.*not one of the allowed types: scalar/;
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col4 => 'val64',
        col1 => 'val61',
        col3 => 'val63',
        # col2 is missing
    });
    $expected .= qq{val64\tval61\tval63\t\n};
    _rewind_and_verify($fh, $expected);

    throws_ok{
        $writer->write({
            col4 => 'val74',
            col1 => 'val71',
            col3 => 'val74',
            col2 => undef, # col2 is not SCALAR
        });
    } qr/'col2'.*not one of the allowed types: scalar/;
    _rewind_and_verify($fh, $expected);

    $writer->close();
}


sub test_reader_as_schema : Test(1) {
    my ($fh1, $fn1) = tempfile(UNLINK => 1);
    print $fh1 qq{col4\tcol1\tcol3\tcol2\nval14\tval11\tval13\tval12\n};
    close $fh1;

    my $reader = File::TabularData::Reader->new(file => $fn1);

    my ($fh2, $fn2) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh2, schema => $reader);

    $writer->write({
        col4 => 'val24',
        col1 => 'val21',
        # col3 is missing
        col2 => 'val22',
    });
    my $expected = qq{col4\tcol1\tcol3\tcol2\nval24\tval21\t\tval22\n};
    _rewind_and_verify($fh2, $expected);

    $writer->close();
    $reader->close();
}


sub test_invalid_schema : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    throws_ok{
        File::TabularData::Writer->new(
            file => $fh,
            schema => 1, # scalar value should be invalid
        );
    } qr/'schema'.*not one of the allowed types/;

    throws_ok {
        File::TabularData::Writer->new(
            file => $fh,
            schema => $fh, # glob value should be invalid
        );
    } qr/'schema'.*not one of the allowed types/;

    throws_ok{
        File::TabularData::Writer->new(
            file => $fh,
            schema => DummyObject->new(), # won't accept object except reader
        );
    } qr/Invalid schema/;
}


sub test_append : Test(2) {
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        print $fh qq{key1\tkey2\nval1\tval2\n};
        close $fh;

        my $writer = File::TabularData::Writer->new(file => $fn, append => 1);
        $writer->write({
            key1 => 'val3',
            key2 => 'val4'
        });
        $writer->close();

        my $results = `cat $fn`;
        is($results, qq{key1\tkey2\nval1\tval2\nval3\tval4\n});
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        print $fh qq{key1\tkey2\nval1\tval2\n};
        close $fh;

        my $writer = File::TabularData::Writer->new(file => $fn, append => 1, style => 'tsv');
        $writer->write({
            key1 => 'val3',
            key2 => 'val4'
        });
        $writer->close();

        my $results = `cat $fn`;
        is($results, qq{key1\tkey2\nval1\tval2\nval3\tval4\n});
    }
}


sub test_append_with_schema : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    print $fh qq{key1\tkey2\nval1\tval2\n};
    close $fh;

    my $writer = File::TabularData::Writer->new(
        file => $fn,
        append => 1,
        schema => [
            key2 => 0, # Wrong order should be acceptable
            key1 => 0,
        ],
    );
    $writer->write({
        key2 => 'val4',
        key1 => 'val3'
    });
    $writer->close();

    my $results = `cat $fn`;
    is($results, qq{key1\tkey2\nval1\tval2\nval3\tval4\n});

    throws_ok{
        File::TabularData::Writer->new(
            file => $fn,
            append => 1,
            schema => [
                # key1 is missing
                key2 => 0,
            ],
        );
    } qr/Schema of the file being appended to does not match with the specified schema/;

    throws_ok{
        File::TabularData::Writer->new(
            file => $fn,
            append => 1,
            schema => [
                key1 => 0,
                key2 => 0,
                key3 => 0, # An extra key
            ],
        );
    } qr/Schema of the file being appended to does not match with the specified schema/;
}


sub test_commit : Test(4) {
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        close $fh;
        unlink $fn;

        my $writer = File::TabularData::Writer->new(file => $fn, require_commit => 1);
        $writer->write({a => 1});
        $writer->close;
        ok(not -f $fn); # Not commited, file shouldn't exist
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        close $fh;
        unlink $fn;

        my $writer = File::TabularData::Writer->new(file => $fn, require_commit => 1);
        $writer->write({a => 1});
        $writer->rollback;
        $writer->close;
        ok(not -f $fn); # Rollback'ed, file shouldn't exist
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        close $fh;
        unlink $fn;

        my $writer = File::TabularData::Writer->new(file => $fn, require_commit => 1);
        $writer->write({a => 1});
        $writer->commit;
        ok(-f $fn); # Commited, file should be written

        is_deeply(
            [File::TabularData::Reader->new(file => $fn)->slurp],
            [{a => 1}],
        );
    }
}


sub test_encodong : Test(2) {
    my ($fh, $fn) = tempfile(UNLINK => 1);

    # Die un unknown encoding.
    throws_ok{
        File::TabularData::Writer->new(file => $fh, encoding => 'unknownencodingname')
    } qr/Unknown encoding/;

    # Write Japanese in Korean encoding
    my $word = 'こんいちわ';
    my $writer = new File::TabularData::Writer(file => $fh, bom => 'never', encoding => 'euc-kr');
    $writer->write({ word => $word });
    close $fh;

    # Read in same encoding.
    open my $fh2, '<:encoding(euc-kr)', $fn;
    my $reader = File::TabularData::Reader->new(file => $fh2);
    my @rows = $reader->slurp;
    is($word, $rows[0]->{word});
}


sub test_encoding_and_bom : Test(8) {
    my $encoding_names = {
        'utf-16le' => 'UTF-16LE',
        'utf-16be' => 'UTF-16BE',
        'utf-32le' => 'UTF-32LE',
        'utf-32be' => 'UTF-32BE'
    };

    foreach my $encoding_name (keys %$encoding_names) {
        my ($fh1, $fn1) = tempfile(UNLINK => 1);

        my $data = { enu => 'foobar', ja => '大丈夫です' };
        my $writer = File::TabularData::Writer->new(file => $fn1, bom => 'always', encoding => $encoding_name);
        $writer->write($data);
        $writer->close;

        # Verify encoding
        my ($fh2, $encoding) = open_bom($fn1);
        is($encoding, $encoding_names->{$encoding_name});

        # Read in, encoding determined by BOM
        my ($got) = File::TabularData::Reader->new(file => $fn1)->slurp;
        is_deeply($data, $got);
    }
}


sub test_print_header : Test(5) {
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        my $writer = File::TabularData::Writer->new(file => $fh); # use default
        $writer->close();
        my $result = `cat $fn`;
        is($result, '');
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        my $writer = File::TabularData::Writer->new(file => $fh, print_header => 'first_row');
        $writer->write({col3 => 'val3', col1 => 'val1', col2 => 'val2'});
        $writer->close();
        my $result = `cat $fn`;
        is($result, qq{col1\tcol2\tcol3\nval1\tval2\tval3\n});
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        my $writer = File::TabularData::Writer->new(file => $fh, print_header => 'always');
        $writer->close();
        my $result = `cat $fn`;
        is($result, ''); # Nothing, because there's no schema
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        my $writer = File::TabularData::Writer->new(file => $fh, print_header => 'always', schema => [ col3 => 0, col1 => 0, col2 => 0]);
        $writer->close();
        my $result = `cat $fn`;
        is($result, qq{col3\tcol1\tcol2\n});
    }
    {
        my ($fh, $fn) = tempfile(UNLINK => 1);
        my $writer = File::TabularData::Writer->new(file => $fh, print_header => 'never', schema => [ col3 => 0, col1 => 0, col2 => 0]);
        $writer->write({col3 => 'val3', col1 => 'val1', col2 => 'val2'});
        $writer->close();
        my $result = `cat $fn`;
        is($result, qq{val3\tval1\tval2\n});
    }
}


sub test_remove_newline_in_data : Test(1) {
    my ($fh, $fn) = tempfile(UNLINK => 1);

    my $writer = File::TabularData::Writer->new(file => $fh);
    $writer->write({ col1 => 'val1', col2 => "val2\r\nnewline1\r\nnewline2" });
    $writer->close;

    my $result = `cat $fn`;
    is($result, qq{col1\tcol2\nval1\tval2 newline1 newline2\n});
}


sub test_style_tsv : Test(2) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh);

    my $warnings = catch_warnings{
        $writer->write({ col1 => "value\twith\ttabs", col2 => "another value\twith tabs" });
    };
    like($warnings, qr/Got tabs in data/);
    $writer->close;

    my @results = File::TabularData::Reader->new(file => $fn)->slurp;
    is_deeply(
        $results[0], {
            col1 => 'value    with    tabs',
            col2 => 'another value    with tabs'
        }
    );
}


sub test_style_csv : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh, style => 'csv');
    $writer->write({
        col1 => 'val11',
        col2 => 'val12',
    });
    my $expected = qq{col1,col2\nval11,val12\n};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col1 => 'val21',
        col2 => 'val22',
    });
    $expected .= qq{val21,val22\n};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col1 => 'some "quotes" in data',
        col2 => 'some,comma,in,data',
    });
    $expected .= qq{"some ""quotes"" in data","some,comma,in,data"\n};
    _rewind_and_verify($fh, $expected);

    $writer->close;
}


sub test_style_other_delimited : Test(2) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh, delimiter => '|');

    $writer->write({
        col1 => 'val11',
        col2 => 'val12',
    });
    my $expected = qq{col1|col2\nval11|val12\n};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col1 => 'val21',
        col2 => 'val22',
    });
    $expected .= qq{val21|val22\n};
    _rewind_and_verify($fh, $expected);

    $writer->close;
}


sub test_style_html : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh, style => 'html');

    $writer->write({
        col1 => 'val11',
        col2 => 'val12',
    });
    my $expected = qq{<html><body><meta http-equiv='Content-Type' content='text/html; charset=UTF-8'/>
<table><tr><th>col1</th><th>col2</th></tr>
<tr><td>val11</td><td>val12</td></tr>
};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col1 => 'val21',
        col2 => 'val22',
    });
    $expected .= qq{<tr><td>val21</td><td>val22</td></tr>\n};
    _rewind_and_verify($fh, $expected);

    $writer->close();

    $expected .= qq{</table></body></html>};
    my $results = `cat $fn`;
    is($results, $expected);
}


sub test_style_xml : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    my $writer = File::TabularData::Writer->new(file => $fh, style => 'xml');

    $writer->write({
        col1 => 'val11',
        col2 => 'val12',
        col3 => 'val13',
        col4 => 'val14',
    });
    my $expected = qq{<?xml version="1.0" encoding="UTF-8"?>
<xml><body><table><tr><th>col1</th><th>col2</th><th>col3</th><th>col4</th></tr>
<tr><td>val11</td><td>val12</td><td>val13</td><td>val14</td></tr>
};
    _rewind_and_verify($fh, $expected);

    $writer->write({
        col1 => "<\n>",
        col2 => '>',
        col3 => '"',
        col4 => '&',
    });
    $expected .= qq{<tr><td>&lt;
&gt;</td><td>&gt;</td><td>&quot;</td><td>&amp;</td></tr>\n};
    _rewind_and_verify($fh, $expected);

    $writer->close();

    $expected .= qq{</table></body></xml>};
    my $results = `cat $fn`;
    is($results, $expected);
}


# this test will fork the process, let the child DLMWriter to hold the file for writing
# for 3 seconds, then let the parent DLMWriter try to obtain the write permission over
# the same file. the parent should failed and die because it does not use wait_for_lock flag.
sub test_dont_wait_for_lock : Test(1) {
    my ($fh, $fn) = tempfile(UNLINK => 0);
    close($fh);

    my $pid;
    eval {
        $pid = fork;
        die "failed to fork: $! \n" unless defined $pid;
        if ($pid) {
            # this is the parent
            sleep 1;
            throws_ok {
                my $writer = File::TabularData::Writer->new(
                    file => $fn,
                    require_commit => 1,
                );
            } qr/cannot lock on this file/;
        }
        else {
            # child
            my $writer = File::TabularData::Writer->new(
                file => $fn,
                require_commit => 1,
            );
            # hold lock for a while..
            sleep 3;
            exit;
        }
    };
    my $error = $@;
    if ($pid) {
        unlink $fn;
        die $error . "\n" if $error;

        my $kid;
        do {
            $kid = wait;
        } until $kid > 0;
    }
    else {
        exit;
    }
}


# similar to above test: this test will fork the process, let the child DLMWriter to hold
# the file for writing for 3 seconds, then let the parent DLMWriter try to obtain the write
# permission over the same file. the parent should be able to get the permission after waiting
# couple seconds after child release the lock, because the parent uses wait_for_lock flag.
sub test_wait_for_lock : Test(1) {
    my ($fh, $fn) = tempfile(UNLINK => 0);
    close($fh);

    my $pid;
    eval {
        $pid = fork;
        die "failed to fork: $! \n" unless defined $pid;
        if ($pid) {
            # this is the parent
            sleep 1;
            my $writer = File::TabularData::Writer->new(
                file => $fn,
                wait_for_lock => 1,
                require_commit => 1,
            );
            ok($writer);
            $writer->close;
        }
        else {
            # child
            my $writer = File::TabularData::Writer->new(
                file => $fn,
                require_commit => 1,
            );
            # hold lock for a while...
            sleep 3;
            $writer->close;
            exit;
        }
    };
    my $error = $@;
    if ($pid) {
        unlink $fn;
        die $error . "\n" if $error;

        my $kid;
        do {
            $kid = wait;
        } until $kid > 0;
    }
    else {
        exit;
    }
}


sub test_wait_for_lock_without_require_commit : Test(1) {
    my ($fh, $fn) = tempfile(UNLINK => 1);
    close($fh);

    throws_ok {
        my $new_writer = File::TabularData::Writer->new(
            file => $fn,
            wait_for_lock => 1,
        );
    } qr/'wait_for_lock' without 'require_commit'/;
}


# fork the process, let child hold the file lock for a while, and let parent try to obtain
# write permission for same file. while child locks the file (.generating file is true),
# parent's _waited_for_lock is true. otherwise, it's false.
sub test_avoid_writing_same_file_with_commit : Test(3) {
    my ($fh, $fn) = tempfile(UNLINK => 0);
    close($fh);

    my $pid;
    eval {
        $pid = fork;
        die "failed to fork: $! \n" unless defined $pid;
        if ($pid) {
            # this is the parent
            sleep 1;
            my $writer = File::TabularData::Writer->new(
                file => $fn,
                wait_for_lock => 1,
                require_commit => 1,
            );
            ok($writer->_waited_for_lock);
            my $results = `cat $fn`;
            is($results, qq{col1\nval1\n});

            # now test again after no cache file.
            my $writer2 = File::TabularData::Writer->new(
                file => $fn,
                wait_for_lock => 1,
                require_commit => 1,
            );
            ok(not $writer2->_waited_for_lock);
            unlink($fn);
        }
        else {
            # child
            my $writer = File::TabularData::Writer->new(
                file => $fn,
                require_commit => 1,
            );
            $writer->write({ col1 => 'val1' });
            # now hold the lock for a while...
            sleep 3;
            $writer->commit;
            $writer->close;
            exit;
        }
    };
    my $error = $@;
    if ($pid) {
        unlink $fn;
        die $error . "\n" if $error;

        my $kid;
        do {
            $kid = wait;
        } until $kid > 0;
    }
    else {
        exit;
    }
}


package DummyObject;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}
