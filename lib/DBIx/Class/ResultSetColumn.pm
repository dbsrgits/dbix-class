package DBIx::Class::ResultSetColumn;
use strict;
use warnings;
use base 'DBIx::Class';
use List::Util;

=head1 NAME

  DBIx::Class::ResultSetColumn - helpful methods for messing
  with a single column of the resultset

=head1 SYNOPSIS

  $rs = $schema->resultset('CD')->search({ artist => 'Tool' });
  $rs_column = $rs->get_column('year');
  $max_year = $rs_column->max; #returns latest year

=head1 DESCRIPTION

A convenience class used to perform operations on a specific column of
a resultset.

=cut

=head1 METHODS

=head2 new

  my $obj = DBIx::Class::ResultSetColumn->new($rs, $column);

Creates a new resultset column object from the resultset and column
passed as params. Used internally by L<DBIx::Class::ResultSet/get_column>.

=cut

sub new {
  my ($class, $rs, $column) = @_;
  $class = ref $class if ref $class;
  my $new_parent_rs = $rs->search_rs; # we don't want to mess up the original, so clone it
  my $attrs = $new_parent_rs->_resolved_attrs;
  $new_parent_rs->{attrs}->{$_} = undef for qw(prefetch include_columns +select +as); # prefetch, include_columns, +select, +as cause additional columns to be fetched

  # If $column can be found in the 'as' list of the parent resultset, use the
  # corresponding element of its 'select' list (to keep any custom column
  # definition set up with 'select' or '+select' attrs), otherwise use $column
  # (to create a new column definition on-the-fly).
  my $as_list = $attrs->{as} || [];
  my $select_list = $attrs->{select} || [];
  my $as_index = List::Util::first { ($as_list->[$_] || "") eq $column } 0..$#$as_list;
  my $select = defined $as_index ? $select_list->[$as_index] : $column;

  my $new = bless { _select => $select, _as => $column, _parent_resultset => $new_parent_rs }, $class;
  $new->throw_exception("column must be supplied") unless $column;
  return $new;
}

=head2 as_query

=over 4

=item Arguments: none

=item Return Value: \[ $sql, @bind ]

=back

Returns the SQL query and bind vars associated with the invocant.

=cut

sub as_query { return shift->_resultset->as_query }

=head2 as_subselect

=over 4

=item Arguments: none

=item Return Value: \[ $sql, @bind ]

=back

Returns the SQL query and bind vars associated with the invocant.

The SQL will be wrapped in parentheses, ready for use as a subselect.

=cut

sub as_subselect {
  my $self = shift;
  my $arr = ${$self->as_query(@_)};
  $arr->[0] = '( ' . $arr->[0] . ' )';
  return \$arr;
}

=head2 as_query

=over 4

=item Arguments: none

=item Return Value: $sql

=back

Returns the SQL query associated with the invocant. All bind vars
will have been bound using C<< DBI->quote() >>.

=cut

sub as_sql {
  my $self = shift;
  my $arr = ${$self->as_query(@_)};
  my $sql = shift @$arr;
  my $dbh = $self->_resultset->result_source->schema->storage->dbh;
  $sql =~ s/\?/$dbh->quote((shift @$arr)->[1])/eg;
  return $sql
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: $value

=back

Returns the next value of the column in the resultset (or C<undef> if
there is none).

Much like L<DBIx::Class::ResultSet/next> but just returning the 
one value.

=cut

sub next {
  my $self = shift;
  my ($row) = $self->_resultset->cursor->next;
  return $row;
}

=head2 all

=over 4

=item Arguments: none

=item Return Value: @values

=back

Returns all values of the column in the resultset (or C<undef> if
there are none).

Much like L<DBIx::Class::ResultSet/all> but returns values rather
than row objects.

=cut

sub all {
  my $self = shift;
  return map { $_->[0] } $self->_resultset->cursor->all;
}

=head2 reset

=over 4

=item Arguments: none

=item Return Value: $self

=back

Resets the underlying resultset's cursor, so you can iterate through the
elements of the column again.

Much like L<DBIx::Class::ResultSet/reset>.

=cut

sub reset {
  my $self = shift;
  $self->_resultset->cursor->reset;
  return $self;
}

=head2 first

=over 4

=item Arguments: none

=item Return Value: $value

=back

Resets the underlying resultset and returns the next value of the column in the
resultset (or C<undef> if there is none).

Much like L<DBIx::Class::ResultSet/first> but just returning the one value.

=cut

sub first {
  my $self = shift;
  my ($row) = $self->_resultset->cursor->reset->next;
  return $row;
}

=head2 min

=over 4

=item Arguments: none

=item Return Value: $lowest_value

=back

  my $first_year = $year_col->min();

Wrapper for ->func. Returns the lowest value of the column in the
resultset (or C<undef> if there are none).

=cut

sub min {
  return shift->func('MIN');
}

=head2 max

=over 4

=item Arguments: none

=item Return Value: $highest_value

=back

  my $last_year = $year_col->max();

Wrapper for ->func. Returns the highest value of the column in the
resultset (or C<undef> if there are none).

=cut

sub max {
  return shift->func('MAX');
}

=head2 sum

=over 4

=item Arguments: none

=item Return Value: $sum_of_values

=back

  my $total = $prices_col->sum();

Wrapper for ->func. Returns the sum of all the values in the column of
the resultset. Use on varchar-like columns at your own risk.

=cut

sub sum {
  return shift->func('SUM');
}

=head2 func

=over 4

=item Arguments: $function

=item Return Value: $function_return_value

=back

  $rs = $schema->resultset("CD")->search({});
  $length = $rs->get_column('title')->func('LENGTH');

Runs a query using the function on the column and returns the
value. Produces the following SQL:

  SELECT LENGTH( title ) FROM cd me

=cut

sub func {
  my ($self,$function) = @_;
  my $cursor = $self->{_parent_resultset}->search(undef, {select => {$function => $self->{_select}}, as => [$self->{_as}]})->cursor;
  
  if( wantarray ) {
    return map { $_->[ 0 ] } $cursor->all;
  }

  return ( $cursor->next )[ 0 ];
}

=head2 throw_exception

See L<DBIx::Class::Schema/throw_exception> for details.
  
=cut 
    
sub throw_exception {
  my $self=shift;
  if (ref $self && $self->{_parent_resultset}) {
    $self->{_parent_resultset}->throw_exception(@_)
  } else {
    croak(@_);
  }
}

# _resultset
#
# Arguments: none
#
# Return Value: $resultset
#
#  $year_col->_resultset->next
#
# Returns the underlying resultset. Creates it from the parent resultset if
# necessary.
# 
sub _resultset {
  my $self = shift;

  return $self->{_resultset} ||= $self->{_parent_resultset}->search(undef,
    {
      select => [$self->{_select}],
      as => [$self->{_as}]
    }
  );
}

1;

=head1 AUTHORS

Luke Saunders <luke.saunders@gmail.com>

Jess Robinson

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
