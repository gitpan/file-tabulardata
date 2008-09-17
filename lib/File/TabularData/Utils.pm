# Copyright (c) 2008 Yahoo! Inc.  All rights reserved.  This program is free
# software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License (GPL), version 2 only.  This program is distributed
# WITHOUT ANY WARRANTY, whether express or implied. See the GNU GPL for more
# details (http://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

package File::TabularData::Utils;

use strict;
use warnings;

use Carp;
use Exporter;
use File::BOM qw/open_bom/;
use Params::Validate ':all';
use Scalar::Util 'reftype';

my @constants = ();

my @functions = qw(
    catch_warnings
    lines_in_file
    make_order_hash
    open_file
    sets_equal
    sort_by
    install_accessors
);

our @ISA         = qw(Exporter);
our @EXPORT_OK   = (@constants, @functions);
our %EXPORT_TAGS = (
    all       => \@EXPORT_OK,
    constants => \@constants,
    functions => \@functions,
);

=head2 catch_warnings

Works like an eval{} block, except warnings also raise exceptions that go into $@.

=cut

sub catch_warnings(&) {
    my $coderef = shift;
    my $warning = '';
    $@ = undef;
    local $SIG{__WARN__} = sub {
        $warning .= shift;
    };
    &$coderef;
    $@ = $warning if $warning;
    return $warning;
}

=head2 lines_in_file

Counts lines in file using wc -l.

    my $nlines = lines_in_file('myfile.txt');

=cut

sub lines_in_file {
    my $filename = shift;
    croak "Expected filename ($filename)" if not($filename) or ref $filename;
    croak "No such file $filename" if not -f $filename;
    my $lines = `wc -l $filename 2>&1`;
    $lines =~ /(\d+)/;
    return $1;
}

=head2 make_order_hash

Converts an array into a hash, where keys are items in the array, and values are orders of those items in original array.

=cut

sub make_order_hash {
    my $array = shift;
    my ($n, $order) = (0, {});
    $order->{$_} = $n++ for (@$array);
    return $order;
}

=head2 open_file

DOCUMENT ME

=cut

sub open_file {
    my ($file, $encoding) = @_;
    my ($filename, $handle);

    if (not ref $file) {
        # Support convention of '-' meaning STDIN
        if ($file eq '-') {
            $filename = $file;
            $handle = \*STDIN;
            binmode(STDIN, ':utf8');
        }
        else {
            $filename = $file;

            # if an encoding is specified, 'try' to open in that encoding
            if ($encoding) {
                ($handle, $encoding) = eval {
                    open_bom($file, ':encoding(' . $encoding . ')')
                };
            }
            else {
                ($handle, $encoding) = eval {
                    open_bom($file, ':utf8')
                };
            }
            croak $@ if $@;
            croak "Error opening $file: $!" unless $handle;
        }
    }
    else {
        # If your passing in a handle, open in proper encoding and convert to utf8 your self
        $handle = $file;
    }
    return ($filename, $handle, $encoding);
}

=head2 sets_equal

    sets_equal([1, 2, 3], [3, 2, 1]) or die "sets_equal doesn't work";

=cut

sub sets_equal {
    my ($set1, $set2) = @_;

    ### First, convert array2 to hash, if it isn't already one:
    my $hash1 =
        reftype($set1) eq 'HASH'
        ? $set1
        : reftype($set1) eq 'ARRAY'
        ? { map {$_ => 1} @$set1 }
        : croak "Expected array or hash reference in second argument to is_subset"
    ;

    ### First, convert array2 to hash, if it isn't already one:
    my $hash2 =
        reftype($set2) eq 'HASH'
        ? $set2
        : reftype($set2) eq 'ARRAY'
        ? { map {$_ => 1} @$set2 }
        : croak "Expected array or hash reference in second argument to is_subset"
    ;

    foreach my $member (keys %$hash1) {
        return 0 if not $hash2->{$member};
    }
    foreach my $member (keys %$hash2) {
        return 0 if not $hash1->{$member};
    }

    return 1;
}

=head2 sort_by

Easier way of saying sort {$a->property <=> $b->property} @array

    sort_by { $_->property } @array

=cut

### Extend the map/grep/sort repertoire of array manipulation concepts
sub sort_by(&@) {
    my $coderef = shift;

    my $values = {};
    return sort {
        my $vala = $values->{$a};
        $vala = $values->{$a} = do {local $_ = $a; $coderef->()} if not defined $vala;

        croak "Error evaluating callback" if $@;

        my $valb = $values->{$b};
        $valb = $values->{$b} = do {local $_ = $b; $coderef->()} if not defined $valb;

        croak "Error evaluating callback" if $@;
        croak "Expression should return value in sort_by" if not defined $vala or not defined $valb;

        $vala <=> $valb
    } @_;
}

=head2 install_accessors

?

=cut

sub install_accessors {
    my ($class, $parameters, @extra) = @_;

    croak "Argument to install_accessors should be single arrayref or hashref" if @extra ;

    $parameters or confess "No attrib";
    
    # Normalize Params::Validate spec, so it's always a hash of key => hashref
    $parameters = _normalize_parameters($parameters);

    foreach my $attribute (keys %$parameters) {
        no strict 'refs'; # we will be referencing sub by name
        my $spec = $parameters->{ $attribute };
        my $sub_name = "${class}::${attribute}";
        my $default_sub_name;

        # Get fully qualified name of default sub, if there is one.
        if ($spec->{default_sub}) {
            $default_sub_name = _get_default_sub_name($class, $attribute, $spec->{default_sub});
        }

        # Built an accesor (anonymous subroutine).
        my $new_accessor = _build_accessor(
            $attribute,
            $spec,
            $default_sub_name
        );
        
        # Override without warnings if one of these args is passed
        if ($spec->{default_sub} or $spec->{override}) {
            no warnings; # yeah yeah, we know we are overriding an existing subroutine.
            *{$sub_name} = $new_accessor;
        }

        # Woah!  There's already a subroutine with this name.  The user probably didn't want that unless they explicitly passed the 'override' parameter or are using this as a default_sub.
        elsif (*{$sub_name}{CODE}) {
            croak "Trying to install accessor for existing subroutine '$sub_name'.  Define the accessor with override or default_sub if you really want to do this.  See 'perldoc ".__PACKAGE__."' for more info."
        }
        # Okay, everything is good.  Go ahead and install our accessor!  Hooray!
        else {
            *{$sub_name} = $new_accessor;
        }
    }
}

our $current_method;
Params::Validate::validation_options(
    on_fail => sub {
        my($message) = @_;

        # Error messages generated by Params::Validate::validate
        # assume it is being called from within a named. 
        # But we're calling it from within an anonymous subroutine.
        # So we need to change error messages thrown by Params::Validate
        # to show the name of the accessor, instead of "__ANON__".

        $message =~ s/(?<=Params::Validate::Accessors::)__ANON__/$current_method/g;

        # Now we fixed the message, we can proceed with our death.
        die $message;
    }
);

# Find the fully-qualified subroutine name given a class name and sub name.
# The sub name may be defined in parent class, so this has to be recursive.
sub _resolve_sub {
    my ($class, $sub_name) = @_;
    my $qualified_sub_name = "$class\::$sub_name";

    no strict 'refs';
    my $coderef = *{$qualified_sub_name}{CODE};
    
    # Is such a subroutine even defined in this class?
    if($coderef) {
        return {
            class => $class,
            coderef => $coderef,
        }
    }        

    # Nope.  Better check parent classes?
    my @base_classes = @{"$class\::ISA"};
    foreach my $base_class (@base_classes) {
        my $result = _resolve_sub($base_class, $sub_name);
        return $result if $result;
    }

    return undef;
}

# Get the fully-qualified name of a subroutine that is used as a 'default_sub'.
# This should be simple, right?  But what if the name of the default_sub is the 
# same as the name of the accessor for which it is a default (see OVERRIDING 
# SUBROUTINES section)?  In these cases, we need to be a little tricky.
sub _get_default_sub_name {
    my ($class, $attribute, $default_sub_name) = @_;

    my $default_sub;
    if (not $default_sub_name =~ /\:\:/) {
        my $resolve_result = _resolve_sub($class, $default_sub_name) or
            croak "Unable to resolve sub $class\::$default_sub_name to use as default_sub for attribute $attribute";
        $class = $resolve_result->{class};
        $default_sub = $resolve_result->{coderef};
        $default_sub_name = "$class\::$default_sub_name";
    }
    else {
        no strict 'refs';
        $default_sub = *{$default_sub_name}{CODE} or
            croak "No such sub $default_sub_name to use as default_sub for attribute $attribute";
    }

    # If overriding sub that has same name of attribute
    # Then we need to re-install the default_sub undef a new ame
    if ($default_sub_name eq "${class}::${attribute}") {
        $default_sub_name = "${class}::default_${attribute}";
        no strict 'refs';
        *{$default_sub_name} = $default_sub;
    }

    return $default_sub_name;
}

sub _build_accessor {
    my ($attribute, $validation_spec, $default_sub) = @_;

    confess "Invalid validation spec: ".Dumper($validation_spec) unless ref($validation_spec) eq 'HASH' or not ref($validation_spec);
    
    $validation_spec = {} unless defined $validation_spec;

    my $default = $validation_spec->{default};
    my $optional = $validation_spec->{optional};

    return sub {
        my ($self, $value) = @_;

        croak "Too many arguments to accessor method $attribute" if @_ > 2;

        ### Package invocation
        if (not ref $self) {
            if (int(@_) == 1) {
                # Must have default
                if (defined $default) {
                    return $default;
                }
                # Call the default sub, if there is one.
                elsif ($default_sub) {
                    return $self->$default_sub;
                }
                else {
                    croak "Getter method should be invoked on a reference, not $self";
                }
            } else {
               croak "Setter method should be invoked on a reference, not $self";
            }
        }

        ### For use in error message.  See call to Params::Validate::validation_options above.
        local $current_method = $attribute;

        ### If called as a getter
        if (@_ == 1) {
            # Return (and remember) default value through Params::Validate
            # If there is a 'default' in the validation spec.
            if (not exists $self->{$attribute}) {
                if ($default) {
                    # There's a default, we'll actually *set* this value in this object so we don't have to do this again.
                    ($self, $self->{ $attribute }) =
                        validate_pos( @_, 1, $validation_spec, undef )
                }
                # If there is not a default in validation spec, try a default sub
                elsif ($default_sub) {
                    $self->{ $attribute } = uplevel(2, sub {
                        $self->$default_sub($value);
                    }, @_);
                }
                # Otherwise, this has better be optional.
                elsif ($optional) {
                    return undef;
                } else {
                    croak "Required attribute '$attribute' has not been set!";
                }
            }
            return $self->{ $attribute };
        }
        # Otherwise, it's a setter. Validate first, then set.
        elsif (@_ == 2) {
            ($self, $self->{ $attribute }) =
                validate_pos(@_, 1, $validation_spec);
            return $self;
        }
    };
}

sub _normalize_parameters {
    my ($parameters, %args) = @_;

    confess "Missing attribute list" if not $parameters;

    # An arrayref means we have a list of optional parameters.
    if (ref($parameters) eq 'ARRAY') {
        $parameters = {
            map { $_ => { optional => 1 } } @$parameters
        };
        return $parameters;
    }
    elsif (ref($parameters) eq 'HASH') {
        for my $attribute (keys %$parameters) {
            my $spec = $parameters->{$attribute};
            
            # undef or 0 means optional
            if (not ref $spec) {
                $parameters->{$attribute} = {optional => !$spec};
            }
            # 'default_sub' and 'default' are extra attributes used by Params::Validate::Accessors.  They imply optional.
            elsif ($spec->{default_sub} or $spec->{default}) {
                $spec->{optional} = 1;
            }
        }

    }

    return $parameters;
}

1;
