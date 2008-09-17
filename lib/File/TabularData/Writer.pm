# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Writer;

use strict;
use warnings;

=head1 SYNOPSIS

  # Create the writer
  my $writer = File::TabularData::Writer->new(
      file => 'myfile.tsv',
      style => 'tsv',
      schema => [
            col1 => 0,
            col2 => 0,
            col3 => 0,
      ],
  );

  # Write two rows
  $writer->write({ col1 => 'a', col2 => 'b', col3 => 'c' });
  $writer->write({ col1 => 1, col2 => 2, col3 => 3 });

  # Close the writer
  $writer->close();

=head2 ATOMIC WRITES

  my $writer = File::TabularData::Writer->new(
      file => 'myfile.tsv',
      require_commit => 1,
  );

  $writer->write({ a => 'b' });

  # If we die, we 'roll back' the file we were writing.
  die "Dying a senseless death" if rand() < .5;

  # We didn't die.  Commit file.
  $writer->commit;

=head1 METHODS

=head2 new

Constructor. Parameters:

=over 4

=head3 Mandatory

=over 2

=item file

Name or handle of input file.

=back

=back

=over 4

=head3 Optional

=over 2

=item append

Appends to the specified file.

=item style

Specifies file style: tsv [default], csv, xls, or other_delimited.
If style is 'other_delimited', a delimiter must also be specified.

=item delimiter

Specifies the delimiter if style is 'other_delimited'.

=item encoding

Write file in specified encoding.

=item bom

Valid values are:
  default [default]: a Byte Order Mark will be written except for UTF8.
  always: a BOM will always be written if needed.
  never: no BOM will be written.

Won't write a BOM if you're appending.

=item schema

Defines the schema.
Accepts hashref, arrayref, or an instance of reader.

  Example - hashref:
      schema => {
          col4 => 0,                                 # Data rows may contain this column
            col1 => 1,                                 # Data rows must contain this column
            col3 => { type => SCALAR },                # Data rows must contain this column and the data must be a scalar
            col2 => { optional => 1, type => SCALAR }, # Data rows may contain this column; if this column exists, the data must be a scalar
      },
    Schema should be defined in the syntax of Params::Validate.
    Data rows will be validated with the schema.
    The output column order will be alphabetical, i.e. col1, col2, col3, col4.

  Example - arrayref:
      schema => [
          col4 => 0,
            col1 => 1,
            col3 => { type => SCALAR },
            col2 => { optional => 1, type => SCALAR },
      ],
    Similar to hashref, but preserve the column order.
    So, the output column order will be: col4, col1, col3, col2.

  Example - instance of reader.
      schema => File::TabularData::Reader->new(file => 'myfile1.tsv'),
    The writer will use the column order of 'myfile1.tsv'.

If schema is not specified, the writer will take the columns in the first data row as the schema.
In append mode, if schema is specified, exception will be thrown if the schema of the file being appended to and the specified schema do not match.

=item determine_columns_from_first_row

If set, the writer will only output the columns which the first row has.
Only effective when schema is defined (otherwise, the writer will use the first row anyway).
If ignore_unknown_keys is false, exception will be thrown if the first row contains keys which are not defined in the schema;
Otherwise, the writer will output all the columns in the first row, including those not in the schema.
Does not work in append mode.

=item ignore_unknown_keys

If set, allows quiet passing of unknown keys in data rows;
Otherwise, exception will be thrown.

=item print_header

Specifies if/when to print the header.
Valid values are 'first_row' [default], 'always', 'never'.

=item require_commit

Write to a temporary file and commit when the ->commit method is called explicitly.
If the process dies before this is called, the temporary file is deleted.

=item wait_for_lock

If true, wait for flock released from other process that is holding the lock, then obtain the lock.
If false, it will croak is the file is flocked.
Can only be used with require_commit.

=back

=back

=head2 write

Writes a row.

=head2 flush

Flushes.

=head2 commit

If require_commit is set, calling ->commit will write to the output file and close it.

=head2 rollback

If require_commit is set, calling ->rollback will ignore any changes and close the file.

=head2 close

Close the file.
Note that if require_commit is set, ->commit should be called prior to ->close.

=head1 AUTHOR

YSM DTS Monkeys <ysm-dts-monkeys@yahoo-inc.com>

=cut


use base 'File::TabularData';

use Carp;
use Data::Dumper;
use Fcntl ':flock';
use File::BOM;
use File::NFSLock;
use File::TabularData::Reader;
use File::TabularData::Utils 'install_accessors';
use Params::Validate ':all';


# Parameters' Spec
my $next_id = 0;
sub parameters {
    return {
        file                             => { type => SCALAR | GLOBREF },
        append                           => { default => 0, type => BOOLEAN },
        style                            => { optional => 1, type => SCALAR },
        encoding                         => { default => 'utf8', type => SCALAR },
        delimiter                        => { optional => 1, type => SCALAR },
        bom                              => {
            default => 'default',
            callbacks => {
                'validate' => sub { lc($_[0]) eq 'default' || lc($_[0]) eq 'always' || lc($_[0]) eq 'never' }
            },
        },
        schema                           => { optional => 1, type => HASHREF | ARRAYREF | OBJECT },
        determine_columns_from_first_row => { default => 0, type => BOOLEAN },
        ignore_unknown_keys              => { default => 0, type => BOOLEAN },
        print_header                     => {
            default => 'first_row',
            callbacks => {
                'validate' => sub { lc($_[0]) eq 'first_row' || lc($_[0]) eq 'always' || lc($_[0]) eq 'never' }
            },
        },
        require_commit                   => { default => 0, type => BOOLEAN },
        wait_for_lock                    => { default => 0, type => BOOLEAN },

        # Private
        _id                          => { default => $next_id++ },
        _file_handle                 => 0,
        _file_to_commit              => 0,
        _handler                     => 0,
        _column_order                => 0,
        _header_fields_map           => 0,
        _lock                        => 0,
        _same_generating_file_exists => 0,
        _closed                      => { default => 0 },
        _initialized                 => { default => 0 },
    };
}
install_accessors(__PACKAGE__, parameters);


# Handlers
my %HANDLER_CLASSES = (
    other_delimited => 'File::TabularData::Writers::GenericText',
    csv => 'File::TabularData::Writers::CSV',
    tsv => 'File::TabularData::Writers::TSV',
    xml => 'File::TabularData::Writers::XML',
    html => 'File::TabularData::Writers::HTML',
);

my %LOADED_HANDLERS;
sub _create_handler {
	my ($style, %args) = @_;
	my $handler_class = $HANDLER_CLASSES{lc($style)};
	unless ($LOADED_HANDLERS{$handler_class}) {
		eval "use $handler_class;";
		$LOADED_HANDLERS{$handler_class} = 1;
	}
	return $handler_class->new(%args);
}


# Constructor
sub new {
    my ($class, %args) = @_;
    validate_with(params => \%args, spec => parameters);
    my $self = bless {}, $class;
    while (my ($k, $v) = each %args) {
    	$self->$k($v);
    }

    # Validate/Set the style
    if (!$self->style && (my $dlm = $self->delimiter)) {
        $self->style('other_delimited');
        $self->_handler(_create_handler($self->style, delimiter => $dlm));
    }
    elsif (!$self->style) {
        $self->style('tsv');
        $self->_handler(_create_handler($self->style));
    }
    else {
        defined($HANDLER_CLASSES{lc($self->style)}) or croak "Invalid style: '" . $self->style . "'";
        $self->_handler(_create_handler($self->style, delimiter => $self->delimiter));
    }

    # Get proper encoding name
    my $encoding = Encode::resolve_alias($self->encoding) or croak "Unknown encoding '" . $self->encoding . "'.";
    $self->encoding($encoding);

    if ($self->schema) {
        # Schema is an array: Make it into a hash and save the order into _column_order
        if (ref($self->schema) eq 'ARRAY') {
            my $column_order = [];
            for (my $i = 0; $i < int(@{$self->schema}); $i += 2) {
                push @$column_order, $self->schema->[$i];
            }
            $self->_column_order($column_order);
            $self->schema({ @{$self->schema} });
        }
        # Schema is a hash: Make the _column_order in alphabetical order
        elsif (ref($self->schema) eq 'HASH') {
            $self->_column_order([ sort {$a cmp $b} keys %{$self->schema} ]);
        }
        # Schema is an instance of reader: Take the header_fields as the column order
        elsif (UNIVERSAL::isa($self->schema, 'File::TabularData::Reader')) {
            $self->_column_order($self->schema->header_fields);
            $self->schema({ map { $_ => 0 } @{$self->_column_order} });
        }
        else {
            croak "Invalid schema";
        }
    }

    # If we need to append to a file, verify the schema of the file being appended to.
    if ($self->append) {
        croak "Append is not supported for specified style" unless $self->_handler->support_append;
        croak "'determine_columns_from_first_row' cannot be used in append mode" if $self->determine_columns_from_first_row;
        if (not ref($self->file)) {
            if (-f $self->file) {
                # Open the file and get the header fields
                my $order = File::TabularData::Reader->new(
                    file => $self->file,
                    style => $self->style,
                )->header_fields();

                if ($self->_column_order and not File::TabularData::Utils::sets_equal($self->_column_order, $order)) {
                    croak "Schema of the file being appended to does not match with the specified schema";
                } else {
                    $self->_column_order($order);
                    $self->schema({ map { $_ => 0 } @{$self->_column_order} });
                }

                $self->_header_fields_map({ map {$_ => 1} @{$self->_column_order} });
            }
            else {
                $self->append(0);
            }
        } else {
            croak "Must pass a file name when using append, not [" . $self->file . "]";
        }
    }

    # Opens the file
    my $handle;
    if (not ref($self->file)) {
        my $mode = $self->append ? ">>" : ">";

        # 'require_commit' option says write to a temp file, and only 'commit' changes if the commit method is called.
        if ($self->require_commit) {
            croak "can't implement 'require_commit' if 'mode' is 'append'" if $self->append;
            $self->_file_to_commit($self->file);
            $self->file($self->file . ".generating");

            # Lock the file - lock can only work with 'require_commit'
            my $lock;
            if ($self->wait_for_lock) {
                # Wait for the locked file to release, and try to lock again.
                my $is_waiting_for_lock = 0;
                until ($lock = File::NFSLock->new({ file => $self->file, lock_type => LOCK_EX | LOCK_NB })) {
                    print "Waiting for lock to release on " . $self->file . " ...\n";
                    sleep 5;
                    $is_waiting_for_lock++;
                }
                # Mark there is already a process doing same job we trying to do, and record the done filename.
                $self->_same_generating_file_exists($self->_file_to_commit || $self->file) if $is_waiting_for_lock;
            } else {
                # Do not wait, just croak.
                $lock = File::NFSLock->new({ file => $self->file, lock_type => LOCK_EX | LOCK_NB });
                if (not $lock) {
                    croak "cannot lock on this file: '" . $self->file . "'.";
                }
            }
            $self->_lock($lock);
        } else {
            croak "Can't use 'wait_for_lock' without 'require_commit'" if $self->wait_for_lock;
        }

        open $handle, $mode, $self->file or croak "Error opening " . $self->file . ": $!";
    } else {
        croak "Can't implement 'require_commit' unless 'file' is a file name." if $self->require_commit;
        $handle = $self->file;
    }
    $self->_file_handle($handle);

    # Set encoding
    # Append ':utf8' at the end of layer for Perl < 5.8.7
    my $layer = ":encoding($encoding)";
    if ($self->bom eq 'always' || ($self->bom eq 'default' && $encoding ne 'utf8')) {
        $layer .= ":via(File::BOM):utf8";
    }
    binmode($handle, $layer);

    # Initialized!
    $self->_initialized(1);
    return $self;
}


sub _write_header {
    my $self = shift;

    return if $self->_header_fields_map;
    return unless $self->_column_order;
    return if $self->append;
    return if lc($self->print_header) eq 'never';

       my $handle = $self->_file_handle or confess "File handle is invalid";
    my $header = $self->_handler->generate_header($self->_column_order);
    print $handle $header or croak "Error printing to file handle";
    $self->_header_fields_map({ map {$_ => 1} @{$self->_column_order} });
}


sub _write_footer {
    my $self = shift;
    my $footer = $self->_handler->generate_footer($self->_column_order);
    if ($footer) {
        my $handle = $self->_file_handle or confess "File handle is invalid";
        print $handle $footer or croak "Error printing to file handle";
    }
}


sub write {
    my ($self, $row) = @_;
    croak "Hashref is expected" unless ref($row) eq 'HASH';

    my $handle = $self->_file_handle or confess "File handle is invalid";

    # If _column_order is not defined, use the hash keys of first row
    if (not $self->_column_order) {
        $self->_column_order([ sort {$a cmp $b} keys %$row ]);
        $self->schema({ map { $_ => 0 } @{$self->_column_order} });
    }

    # If write_all_columns_in_schema is false, we only output the columns which the first row has
    if ($self->determine_columns_from_first_row) {
        my $order = File::TabularData::Utils::make_order_hash($self->_column_order);
        $self->_column_order([ File::TabularData::Utils::sort_by { $order->{$_} || 999999 } keys %$row ]);

        # There's no need to update the schema.
        # If the first row contains unknown keys, we should let 'validate_with' die.
        # If ignore_unknown_keys is set, everything is fine.
    }

    # Validate the row with the schema
    eval {
        validate_with(
            params => $row,
            allow_extra => $self->ignore_unknown_keys,
            spec => $self->schema,
        );
    };
    if ($@) {
        my $error = $@;

        # Give better error message to common errors
        if ($error =~ /not listed in the validation options: (.*)/) {
            croak "The following key in the input hash is not listed in schema: $1";
        }

        # Re-throw
        die $error . "\n";
    }

    # '_write_header' will determine if the header has already been written
    $self->_write_header;

    # Make sure the _column_order won't be evaluated again after the header is written
    $self->determine_columns_from_first_row(0);

    # Serialize the data and write it to the handle
    my $warning = File::TabularData::Utils::catch_warnings {
        my $serialized = $self->_handler->generate_row($self->_column_order, $row);
        print $handle $serialized;
    };
    if ($warning) {
        if ($warning =~ /Wide character in print/) {
            my $problem = first {
                not ( Encode::is_utf8($_) and utf8::valid($_) )
            } values %$row;

            croak "Not UTF8 data in hash [$problem]" if $problem;
            croak "'Wide character in print' error.\nEncoding=" . $self->encoding . "\nData was: " . Dumper($row);
        } else {
            warn $@;
        }
    }

    return $self;
}


sub flush {
    my $self = shift;
    $self->_file_handle->flush;
}


sub close {
    my ($self, $commit) = @_;
    return if $self->_closed;

    # So empty files still have a header.
    $self->_write_header if lc($self->print_header) eq 'always';

    if ($self->_file_to_commit && !$commit) {
        $self->rollback;
        return;
    }

    $self->_write_footer;
    $self->_file_handle->close;
    $self->_lock->unlock if $self->_lock;
    $self->_closed(1);
}


sub commit {
    my $self = shift;
    my $file_to_commit = $self->_file_to_commit or croak "Writer wasn't constructed with the require_commit option";
    $self->close(1);
    rename "$file_to_commit.generating", $file_to_commit;
}


sub rollback {
    my $self = shift;
    my $file_to_commit = $self->_file_to_commit or croak "Writer wasn't constructed with the require_commit option";

    $self->_write_footer;
    $self->_file_handle->close;
    $self->_lock->unlock if $self->_lock;
    $self->_closed(1);

    unlink "$file_to_commit.generating";
}

sub _waited_for_lock {
    my $self = shift;
    # return true if we just obtain lock from a the file and the 'completed' file is not zero size.
    return $self->_same_generating_file_exists && (-e $self->_same_generating_file_exists);
}


sub DESTROY {
    my $self = shift;
    $self->close if ($self && $self->_initialized == 1 && $self->_handler);
    # Why _handler sometimes becomes undef?!
}


1;
