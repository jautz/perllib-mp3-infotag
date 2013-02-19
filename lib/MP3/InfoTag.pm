package MP3::InfoTag;

use 5.006;
use Carp;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# This allows   use MP3::InfoTag ':all';
our %EXPORT_TAGS = (
  'typical' => [ qw(getTagFields getTagFieldNames createNewTag printTag
                    setTagField string2tag tag2string) ]
);
our @EXPORT_OK = (
  @{$EXPORT_TAGS{'typical'}},
  qw(flushWarnings getError)
);

our $VERSION = '0.40';



=pod

=head1 NAME

MP3::InfoTag - functions working on ID3 tags



=head1 SYNOPSIS

  use MP3::Info;
  use MP3::InfoTag ':typical';

  my $tag = get_mp3tag($file, 1) || createNewTag();
  print("file '$file': current ID3 tag: ".printTag($tag));

  # write tag fields based on a given string; for better understanding
  # a specific string is used here instead of a variable.  All of these
  # tag fields will be lower case because of the `case => 0' argument.
  my $changed = string2tag(
                  { name => '[02] Iron Maiden - Rainmaker',
                    pattern => '[((TRACKNUM))] ((ARTIST)) - ((TITLE))',
                    tag => $tag,
                    case => 0
                  } );

  # let's be control freaks and look for warnings
  if (my @warnings = MP3::InfoTag::flushWarnings()) {
    print("Warning for file '$file': ".join('; ', @warnings));
  }

  # write changes to file if necessary
  if (!defined $changed) {
    print("file '$file': string2tag failed: ".MP3::InfoTag::getError());
  } elsif ($changed > 0) {
    set_mp3tag($file, $tag);
  }



=head1 DESCRIPTION

This module contains functions for several tasks that occur while working with
ID3 tags of MP3 files.

The functions of this module work with a hash representing the ID3 tag, they do
not manipulate any files.
This module has a tight relationship to the C<MP3::Info> module which uses the
same hash structure.
You'll need to read tags from files and write them to files; for these tasks
C<MP3::Info> provides the necessary operations.

Thus you should regard this module as an extension that provides some functions
which might be useful when working with ID3 tags.

=head2 EXPORT

By default this module does not export any functions into the caller's
namespace.
Anyway, you can export all functions on demand.
For convenience, you may use the keyword ':typical' (see SYNOPSIS)
to export he most important functions, i.e. all functions except of
C<flushWarnings> and C<getError>.

=head2 LIMITATIONS

There are two major types of MPEG Layer 3 tag formats, C<ID3v1> and
C<ID3v2>. Whenever the `ID3 tag' is mentioned in this manual you can
substitute this with C<ID3v1> or more specifically C<ID3v1.1> if the
C<TRACKNUM> field is used. C<ID3v2> tags are not supported.

=cut



# valid tag field names and their recommended order for display
my $TAG_FIELDS_ORDERED = [ 'TITLE', 'ARTIST', 'ALBUM', 'YEAR', 'COMMENT',
                           'TRACKNUM', 'GENRE' ];
# valid tag field names and their max length
my $TAG_FIELDS = { TITLE => 30,
                   ARTIST => 30,
                   ALBUM => 30,
                   YEAR => 4,
                   COMMENT => 30,
                   TRACKNUM => undef,
                   GENRE => undef };

my $DELIM_L = quotemeta('(('); # the left delimiter of a placeholder
my $DELIM_R = quotemeta('))'); # the right delimiter of a placeholder

my $ERROR = '';
my @WARNINGS = ();

=pod

=head1 FUNCTIONS

=over 4

=item flushWarnings

Returns an array containing the warnings produced by functions of this module.
These warnings do not indicate that something is wrong with the program but
rather are informative messages that something happended that the user might
not have expected.
The internal list of warnings will be erased (`flushed') after calling this
function.

=cut

sub flushWarnings {
  my @warns = @WARNINGS;
  @WARNINGS = ();
  return @warns;
}

################################################################################

=pod

=item getError

Returns the string description of the last error that occured.
Errors are typically indicated by an `undef' return value of one of the
functions in this module.
The internal string variable will not be reset by calling this function.

=cut

sub getError {
  return $ERROR;
}

################################################################################

=pod

=item getTagFields

Returns a reference to a hash containing all valid names for tag fields as keys
and their maximum number of characters as values.

=cut

sub getTagFields {
  # return a reference to a copy of this module's hash
  my %fields = (%{$TAG_FIELDS});
  return \%fields;
}

################################################################################

=pod

=item getTagFieldNames

Returns a reference to an array containing all valid names for tag fields.

=cut

sub getTagFieldNames {
  # return a reference to a copy of this module's array
  my @fieldNames = (@{$TAG_FIELDS_ORDERED});
  return \@fieldNames;
}

################################################################################

=pod

=item createNewTag

Returns a reference to a hash representing an empty tag, i.e. all keys' values
are still empty strings.

=cut

sub createNewTag {
  my $tag = {};
  foreach my $field (keys %{$TAG_FIELDS}) {
    $tag->{$field} = '';
  }
  return $tag;
}

################################################################################

=pod

=item printTag(<hashRef> tag [,<boolean> showEmpty])

Creates a string representation for the given C<tag>. Empty fields will be
suppressed unless C<showEmpty> is set to a C<true> value.

Returns the string representation.

=cut

sub printTag {
  my $tag = shift;
  return 'no tag reference given' unless (ref($tag) eq 'HASH');
  my $showEmpty = shift;

  my @strings = ();
  foreach my $field (@{$TAG_FIELDS_ORDERED}) {
    if ($showEmpty  ||  $tag->{$field}) {
      push @strings, $field.': '.$tag->{$field};
    }
  }
  return join(' / ', @strings);
}

################################################################################

=pod

=item setTagField(<hashRef> tag, <string> field, <string> value)

Sets the C<field> of the given C<tag> to C<value>.
Given values are thoroughly checked for validity and, if necessary, warning or
error messages are produced.

Returns C<undef> if an error occured, C<true> otherwise.

=cut

sub setTagField {
  my $tag = shift;
  my $field = shift;
  my $value = shift;

  unless (ref($tag) eq 'HASH') {
    $ERROR = 'tag argument must be a hash reference';
    carp $ERROR;
    return undef;
  }
  unless (defined $field && exists $TAG_FIELDS->{$field} && defined $value) {
    $ERROR = 'valid field and some value must be given';
    return undef;
  }
  $value = _trim($value);

  # check validity of numeric values
  if ($field eq 'YEAR'  &&  $value !~ m/^\d{4}$/) {
    $ERROR = 'field YEAR must be a 4-digit number';
    return undef;

  } elsif ($field eq 'TRACKNUM') {
    unless ($value =~ m/^\d+$/  &&  $value > 0  &&  $value < 256) {
      $ERROR = 'field TRACKNUM must be a number between 1 and 255';
      return undef;

    } elsif ($tag->{COMMENT}) {
      # shorten comment field when implicitly converting to v1.1 tag
      my $comment = $tag->{COMMENT};
      $tag->{COMMENT} = _trim($comment, $TAG_FIELDS->{COMMENT});
      if ($tag->{COMMENT} ne $comment) {
        push @WARNINGS, "setTagField: value of COMMENT must be truncated to ".
                        "'$tag->{COMMENT}' due to addition of TRACKNUM field";
      }
    }

  } else { # string value: trim to max length
    my $fieldLength = $TAG_FIELDS->{$field};
    $fieldLength -= 2 if ($field eq 'COMMENT'  &&  $tag->{TRACKNUM}); # tag v1.1
    my $newValue = _trim($value, $fieldLength);

    if ($newValue ne $value) {
      push @WARNINGS, "setTagField: value of $field must be truncated to ".
                      "'$newValue'";
    }
    $value = $newValue;
  }

  $tag->{$field} = $value;
  return 1;
}

################################################################################

=pod

=item string2tag(<hashRef> args)

Sets the fields of an ID3 tag based upon the information contained in the given
string, which will probably be a filename without extension.

Returns the number of changed tag fields or C<undef> if an error occured.

These are the valid hash entries of C<args>:

=over 4

=item str => <string>

This is the string that holds the information to be extracted and written to
C<tag>.
Usually this will be a filename.

=item pattern => <string>

The C<pattern> defines the format of C<str> by placeholders which indicate the
position of the information to be extracted.
These placeholders have the form ((FIELD)) where FIELD stands for the name
of a tag field.
Placeholder names are case-insensitive.
The name `IGNORE' is also accepted and results in dropping the corresponding
part of C<str> instead of writing it to a tag field.

=item tag => <hashRef>

C<tag> can be an empty tag (see C<createNewTag>) but it is also allowed
to contain values. Some of these will be overwritten as soon as the appropriate
information is extracted from C<str>.

=item case => <int>

[optional]
The string to be written into a tag field is converted according to one of the
following modes:

  0     all characters in lower case
  1     Capitalize the first character, the rest will be lower case
  2     Capitalize The First Character Of Each Word, Even_This-Way

=item weed => <string>

[optional]
A regular expression that will be applied to each string before writing it to a
tag field. Matches will be replaced with a space.

=back

=cut

sub string2tag {
  my $args = shift;
  unless (ref($args) eq 'HASH') {
    $ERROR = 'argument must be a hash reference';
    carp $ERROR;
    return undef;
  }

  my $name = _trim($args->{str});
  unless ($name) {
    $ERROR = 'str argument must contain a non-empty string';
    return undef;
  }
  my $pattern = _normalizePattern(_trim($args->{pattern}));
  unless ($pattern  &&  $pattern =~ m/$DELIM_L\w+$DELIM_R/) {
    $ERROR = 'pattern argument must contain at least one placeholder';
    return undef;
  }
  my $tag = $args->{tag};
  unless (ref($tag) eq 'HASH') {
    $ERROR = 'tag argument must be a hash reference';
    carp $ERROR;
    return undef;
  }
  my $case = $args->{case};
  if (defined $case && $case !~ m/^[012]$/) {
    $ERROR = 'case argument must be one out of [012]';
    carp $ERROR;
    return undef;
  }
  my $weed = $args->{weed};
  if (defined $weed) {
    eval { my $t = 'test'; $t =~ s/$weed/ /g; };
    if ($@) {
      $ERROR = 'weed argument seems to be no valid regular expression';
      carp $ERROR;
      return undef;
    }
  }

  # return value
  my $tagChanged = 0;

  # split all pattern components into array fields
  my @parts = split /($DELIM_L\w+$DELIM_R)/, $pattern;
  my @seperators = ();          # list of placeholders that were used before
  my $pending = '';             # next tag field to be filled

  while (@parts || $pending) {
    my $part = shift @parts;
    # pattern match at the beginning produces leading empty field, skip it:
    next if (defined $part  &&  $part eq ''  &&  @parts > 0);

    if (!defined $part) {
      # ----- PARTS ARRAY EMPTY ----------------------------------------------
      if (@parts == 0  &&  $pending  &&  $name) {
        # all parts were shifted from array but there's a pending field left;
        # set that field's value to the remaining filename, but be cautious:
        foreach my $sep (@seperators) {
          if ($name =~ m/\Q$sep/) {
            $ERROR = "guessing that this filename does not match pattern "
                    ."because '$pending' would be '$name' but this "
                    ."contains '$sep' which was used as seperator before";
            return undef;
          }
        }
        unless ($pending eq 'IGNORE') {
          $name =~ s/$weed/ /g if (defined $weed);
          $name = _convertCase($name, $case) if (defined $case);
          return undef unless setTagField($tag, $pending, $name);
          ++$tagChanged;
        }
        $pending = '';
      } else {
        last;
      }

    } elsif ($part =~ m/$DELIM_L(\w+)$DELIM_R/) {
      # ----- FOUND A PLACEHOLDER --------------------------------------------
      unless (exists $TAG_FIELDS->{$1}  ||  $1 eq 'IGNORE') {
        $ERROR = "unknown placeholder: '$part'";
        return undef;
      }
      if ($pending) {                           # two placeholders side by side
        $ERROR = "two placeholders must be seperated by at least one ".
                 "character; problem occured at '$part'";
        return undef;
      }
      $pending = $1;

    } else {
      # ----- FOUND A SEPERATING STRING --------------------------------------
      push @seperators, $part;  # remember all seperators that were used
      # split $name at first occurence of the seperator
      my ($firstPart, $remainder) = split /\Q$part/, $name, 2;

      if ($firstPart ne $name) {        # got match, i.e. a split took place
        # process both sides of the seperator ...
        # ... left hand side -- pending placeholders ...
        if ($pending) {
          unless ($pending eq 'IGNORE') {
            $firstPart =~ s/$weed/ /g if (defined $weed);
            $firstPart = _convertCase($firstPart, $case) if (defined $case);
            return undef unless setTagField($tag, $pending, $firstPart);
            ++$tagChanged;
          }
          $pending = '';
        }
        # ... right hand side -- remainder of the filename for next iterations
        $name = defined $remainder ? $remainder : '';

      } else {  # $part did not match
        $ERROR = "seperator not found: '$part'";
        return undef;
      } # end (got match?)
    } # end (placeholder || seperator)
  } # end while

  if ($pending) {
    $ERROR = 'no characters found at position of placeholder '.$pending;
    return undef;
  }
  return $tagChanged;
}

################################################################################

=pod

=item tag2string(<hashRef> args)

Generates a string from the information of an ID3 tag.
The format of the string is based upon a given pattern.

Returns C<undef> if an error occured, C<true> otherwise.

These are the valid hash entries of C<args>:

=over 4

=item tag => <hashRef>

C<tag> can be an empty tag (see C<createNewTag>) but it is also allowed
to contain values. Some of these will be overwritten as soon as the appropriate
information is extracted from C<name>.

=item str => <stringRef>

C<str> is an in/out argument.
When this function is called C<str> must contain the pattern mentioned above.
When this function has finished C<str> will contain the
same string but all placeholders like ((TITLE)) will be replaced by the
corresponding C<tag> field's value.
Placeholder names are case-insensitive.

=item case => <int>

[optional]
The result (see C<str>) is converted according to one of the following modes:

  0     all characters in lower case
  1     Capitalize the first character, the rest will be lower case
  2     Capitalize The First Character Of Each Word, Even_This-Way

=back

=cut

sub tag2string {
  my $args = shift;
  unless (ref($args) eq 'HASH') {
    $ERROR = 'argument must be a hash reference';
    carp $ERROR;
    return undef;
  }

  my $tag = $args->{tag};
  unless (ref($tag) eq 'HASH') {
    $ERROR = 'tag argument must be a hash reference';
    carp $ERROR;
    return undef;
  }
  my $str = $args->{str};
  unless (ref($str) eq 'SCALAR') {
    $ERROR = 'str argument must be a scalar reference';
    carp $ERROR;
    return undef;
  }
  $$str = _normalizePattern($$str);

  my @emptyFields = ();
  foreach my $field (keys %{$TAG_FIELDS}) {
    if ($$str =~ m/$DELIM_L$field$DELIM_R/) {
      my $fieldValue = _trim($tag->{$field});

      if (defined $fieldValue  &&  $fieldValue ne '') {
        # warn if a text field is filled to its maximum length because there's
        # a good chance that it was truncated on creation.
        my $maxLength = $TAG_FIELDS->{$field};
        if (defined $maxLength && $field ne 'YEAR' && length($fieldValue) == $maxLength) {
          push @WARNINGS, "tag2string: value of $field has maximum length, ".
                          "you should check if it is truncated: '$fieldValue'";
        }
        # make nice 2-digit numbers of TRACKNUM values
        $fieldValue = sprintf("%02d", $fieldValue) if ($field eq 'TRACKNUM');
        # finally, replace symbol with field's value
        $$str =~ s/$DELIM_L$field$DELIM_R/$fieldValue/g;
      } else {
        # collect undefined or empty tag fields to raise an error summary
        push @emptyFields, $field;
      }
    }
  }

  if (@emptyFields > 0) {
    $ERROR = 'found emtpy tag field(s) required by your pattern: '.
             join(', ', @emptyFields);
    return undef;
  }

  $$str = _convertCase($$str, $args->{case});
  return 1;
}

################################################################################
#
# _normalizePattern(<string> pattern)
#
# Converts the case of the placeholders within the given C<pattern> to
# upper case, e.g. "((tracknum))_((title))" becomes "((TRACKNUM))_((TITLE))".
#
sub _normalizePattern {
  my ($pattern) = @_;
  return undef unless (defined $pattern);

  $pattern =~ s/($DELIM_L\w+$DELIM_R)/\U$1/g;

  return $pattern;
}

################################################################################
#
# _convertCase(<string> line, <int> mode)
#
# Converts the case of the given C<line> of text according to C<mode> which
# can be one of these:
#
#   0     all characters in lower case
#   1     Capitalize the first character, the rest will be lower case
#   2     Capitalize The First Character Of Each Word, Even_This-Way
#
# Returns the converted line or C<undef> if an error occured.
#
sub _convertCase {
  my $line = shift;
  my $mode = shift;

  return undef unless (defined $line);

  return $line unless (defined $mode); # it's simple: no mode, no changes

  if (defined $mode  &&  $mode !~ m/[0-2]/) {
    push @WARNINGS, "convertCase: ignoring unknown conversion mode '$mode'";
    return $line;
  }

  if ($mode == 0) {
    $line =~ tr/A-Z/a-z/;         # all in lower case

  } elsif ($mode == 1) {
    $line =~ tr/A-Z/a-z/;         # all in lower case
    $line = ucfirst $line;        # capitalize first character

  } elsif ($mode == 2) {
    $line =~ tr/A-Z/a-z/;
    $line =~ s/(^[a-z]|(\s|_|-)[a-z])/\U$1/g; # 1st letter of each word capital
  }
  return $line;
}

################################################################################
#
# _trim(<string> str, [<int> len, [<string> truncMarker]])
#
# Removes all leading and trailing whitespace from C<str>.
#
# If C<len> is defined then C<str> will be truncated if it exceeds this maximum
# length.
# By passing a C<truncMarker> you can define a string that is put to the end of
# the string to show that it was truncated (e.g. '...'). The length of the
# resulting string will be exactly C<len> characters.
#
# Returns the trimmed string or C<undef> if an error occured.
#
sub _trim {
  my $str = shift;
  return undef unless (defined $str);
  my $len = shift;
  my $truncMarker = shift;

  $str =~ s/^\s+|\s+$//g; # trim leading and trailing whitespace

  # truncate to the given length if necessary
  if (defined $len  &&  $len >= 0  &&  $len < length($str)) {
    $str = substr $str, 0, $len;

    if (defined $truncMarker  &&  length($truncMarker) < $len) {
      # put one or more chars to the end of the truncated string
      $str = substr($str, 0, $len - length($truncMarker)).$truncMarker;
    }
  }
  return $str;
}

################################################################################

1;

__END__


=pod

=back

=head1 SEE ALSO

C<MP3::Info>



=head1 AUTHOR

Joachim Jautz

http://www.jay-jay.net/contact.html



=head1 COPYRIGHT AND LICENCE

Copyright (c) 2004 Joachim Jautz.  All rights reserved.  This program
is free software; you can redistribute it and/or modify it under the terms
of the Artistic License, distributed with Perl.

=cut
