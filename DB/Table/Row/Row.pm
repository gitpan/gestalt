
package DB::Table::Row;

use Carp qw(cluck confess);
use Data::Dumper;
use strict;

# TODO: use Exception;

=pod
=head1 NAME

DB::Table::Row - provide an interface to a row within a DB::Table object.

=head1 SYNOPSIS

    use DB::Table::Row;
    my $row = DB::Table::Row->construct($dbh, $table, $hashRef);
    $row->insert() || check_for_errors();

    my $userId = $row->userId();
    my $userId = $row->getValue('userId');
    $row->username('newUserName');
    $row->setValue('username', 'newUserName');
    $row->update() || check_for_errors();

    my $row = DB::Table::Row->getByPKey($dbh, $table, $userId);
    $row->delete();

=head1 DESCRIPTION

DB::Table::Row provides an interface to a row in a given database table. It does its best
to prevent the need for writing any custom SQL and also understands foreign-key relationships
and implements constraints on databases which understand the CASE ... END clause.

This module gets its understanding of the table structure that the row is from by being passed
an instance of a DB::Table object (or a sub-class there-of).

=head1 METHODS

=cut

# /* construct */ {{{
=pod

=head2 Class Methods

=over 4

=item my $row = DB::Table::Row->construct($dbh, $table, $hashRef);

This method is used to construct a row object with the structure defined
by $table, with values defined in $hashRef. This method does not actually
insert the row into the given table (See the L<insert()> method), but rather
just constructs in in-memory representation of the row.

=cut
sub construct
{
    # create a new database object

    my $ref   = shift;
    my $class = ref($ref) || $ref;

    my $dbh   = shift;
    my $table = shift || confess("Usage: $class->new(\$dbh, \$table, \$obj)");
    my $obj   = shift || {};

    $obj->{'_dbh'}   = $dbh;
    $obj->{'_table'} = $table;

    # WARNING: This assumes that the first primary key field is the one with the serial column.
    # In most cases it is, but this wont work if it isnt.
    $obj->{($table->primaryKeys())[0]} = undef;

    delete($obj->{'_deleted'});
    delete($obj->{'_modified'});
    delete($obj->{'_validationError'});
    delete($obj->{'_validation'});

    return bless ($obj, $class);
}
# /* construct */ }}}

# /* getByPKey */ {{{
=pod

=item my @rows = DB::Table::Row->getByPKey($dbh, $table, @keys);

This method is used to fetch one or more rows using primary keys.

If used in scalar context (my $row = DB::Table::Row->getByPKey())
then only the first row is actually returned, while in array context
all rows are returned.

If no primary keys are specified, then all rows in the table are returned
(use with caution on very large tables).

You may, however, select a subset of the expected rows by supplying a hash-ref
as the first key, with 'pageLength' being the number of rows you'd like, and
'pageOffset' being the row to start counting from. For example:

  my @rows = DB::Table::Row->getByPKey($dbh, $table, {pageOffset => 100,
                                                      pageLength => 10}
                                       [, @id_list]);
Will only select rows 100 - 110 from the database. You may still supply
an ID list if you choose, in which case you will get back a subset of
rows with the IDs you specify.

Rows are always returned in ncrementing primary key order, ie row[n]'s primary key
will always be smaller than row[n + 1]'s primary key.

=cut
# get the specified object, or a list of them, or all of them
sub getByPKey
{
    my $ref   = shift;
    my $class = ref($ref) || $ref;

    my $dbh   = shift || confess("Usage: $class->getByPKey(\$dbh, \$table [, \@IDs ]);");
    my $table = shift || confess("Usage: $class->getByPKey(\$dbh, \$table [, \@IDs ]);");

    my @obj_ids = @_;
    my $pageOptions = {pageLength => 'ALL',
                       pageOffset => 0};
    if (ref($obj_ids[0]) eq 'HASH')
    {
        $pageOptions = shift @obj_ids;
    }

    my @rows; # Store fetched rows...

    my $get_obj_sql;
    my $numExpectedObjs = scalar(@obj_ids);
    if ($numExpectedObjs > 0)
    {
        $get_obj_sql = sprintf("SELECT %s, %s FROM %s WHERE %s ORDER BY %s LIMIT %s OFFSET %s",
                              join(', ', $table->primaryKeys),
                              join(', ', $table->fields()),
                              $table->name(),
                              join(' AND ', map { "$_ = ?" } $table->primaryKeys()),
                              join(', ', $table->primaryKeys()),
                              $pageOptions->{'pageLength'},
                              $pageOptions->{'pageOffset'});
    }
    else
    {
        $get_obj_sql = sprintf("SELECT %s, %s FROM %s ORDER BY %s LIMIT %s OFFSET %s",
                              join(', ', $table->primaryKeys()),
                              join(', ', $table->fields()),
                              $table->name(),
                              join(', ', $table->primaryKeys()),
                              $pageOptions->{'pageLength'},
                              $pageOptions->{'pageOffset'});
    }
    my $get_obj_sth = $dbh->prepare_cached($get_obj_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $get_obj_sql, $dbh->err, $dbh->errstr));

    do
    {
        my $id = shift @obj_ids;
        my $success;
        if (defined ($id))
        {
            $success = $get_obj_sth->execute(ref($id) eq 'ARRAY' ? @{$id} : $id);
        }
        else
        {
            $success = $get_obj_sth->execute();
        }

        unless ($success)
        {
            # TODO: Raise an exception.
            cluck (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                          $get_obj_sql,
                          (ref($id) eq 'ARRAY' ? @{$id} : $id),
                          $dbh->err,
                          $dbh->errstr));
            return undef;
        }
        my %row = (_dbh   => $dbh,
                   _table => $table);
        $get_obj_sth->bind_columns(map { \$row{$_} } $table->primaryKeys, $table->fields());
        while ($get_obj_sth->fetch)
        {
            my (%newRow) = (%row);
            push @rows, bless (\%newRow, $class);
        }
        $get_obj_sth->finish;
    }
    while (@obj_ids);

    return wantarray ? @rows : $rows[0];
}
# /* getByPKey */ }}}

# /* getByFKey */ {{{
=pod

=item my @rows = DB::Table::Row->getByFKey($dbh, $table, $fKeyName, @FKeys);

This method is used to get all rows from the specified $table object, where
$fKeyName is in the list of FKeys. This method can be used to select
rows where a non-primary-key field is equal to a value supplied in the list
of @FKeys. For example, if you want to get all rows who's 'owner_id' field
is equal to 5, you might say:

  my $row = DB::Table::Row->getByFKey($dbh, $table, 'owner_id', 5);

=cut
sub getByFKey
{
    my $ref   = shift;
    my $class = ref($ref) || $ref;

    my $dbh      = shift || confess("Usage: $class->getByFKey(\$dbh, \$table, \$fKeyName, \@FKeys ]);");
    my $table    = shift || confess("Usage: $class->getByFKey(\$dbh, \$table, \$fKeyName, \@FKeys ]);");
    my $fKeyName = shift || confess("Usage: $class->getByFKey(\$dbh, \$table, \$fKeyName, \@FKeys ]);");
    my @fKeyIds  = @_;

    my @rows; # Store fetched rows...

    my $get_obj_sql;
    my $numExpectedObjs = scalar(@fKeyIds);
    if ($numExpectedObjs > 0)
    {
        $get_obj_sql = sprintf("SELECT %s, %s FROM %s WHERE %s ORDER BY %s",
                              join(', ', $table->primaryKeys()),
                              join(', ', $table->fields()),
                              $table->name(),
                              "$fKeyName = ?",
                              join(', ', $table->primaryKeys()));
    }
    else
    {
        confess("Usage: $class->getByFKey(\$dbh, \$table, \$fKeyName, \@FKeys]);");
    }
    my $get_obj_sth = $dbh->prepare_cached($get_obj_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $get_obj_sql, $dbh->err, $dbh->errstr));

    do
    {
        my $id = shift @fKeyIds;
        my $success;
        if (defined ($id))
        {
            $success = $get_obj_sth->execute($id);
        }

        unless ($success)
        {
            # TODO: Raise an exception.
            cluck (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                          $get_obj_sql,
                          (ref($id) eq 'ARRAY' ? @{$id} : $id),
                          $dbh->err,
                          $dbh->errstr));
            return undef;
        }
        my %row = (_dbh   => $dbh,
                   _table => $table);
        $get_obj_sth->bind_columns(map { \$row{$_} } $table->primaryKeys(), $table->fields());
        while ($get_obj_sth->fetch)
        {
            my (%newRow) = (%row);
            push @rows, bless (\%newRow, $class);
        }
        $get_obj_sth->finish;
    }
    while (@fKeyIds);

    return wantarray ? @rows : $rows[0];
}
# /* getByFKey */ }}}

# /* searchByString */ {{{ 
=pod

=item my @rows = DB::Table::Row->searchByString($dbh, $table, $searchString);

This method allows a free-text search to be performed on the database. All
non-primary-key fields are cast to a string and then search using the LIKE clause.
Searching is not case-sensitive either.

TODO: There is not yet a way to limit which fields are searched, and foreign key's are
not "de-referenced".

=back

=cut
sub searchByString
{
    my $ref = shift;
    my $class = ref($ref) || $ref;

    my $dbh    = shift || confess("Usage: $class->searchByString(\$dbh, \$table, \$string);");
    my $table  = shift || confess("Usage: $class->searchByString(\$dbh, \$table, \$string);");
    my $string = shift || confess("Usage: $class->searchByString(\$dbh, \$table, \$string);");

    my $search_obj_sql = sprintf("SELECT %s, %s FROM %s WHERE %s ORDER BY %s",
                              join(', ', $table->primaryKeys()),
                              join(', ', $table->fields()),
                              $table->name(),
                              join(' OR ', map { "LOWER($_\::text) LIKE ?" } $table->fields()),
                              join(', ', $table->primaryKeys()));
    my $search_obj_sth = $dbh->prepare_cached($search_obj_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $search_obj_sql, $dbh->err, $dbh->errstr));

    my $sucess = $search_obj_sth->execute(map { lc("\%$string\%") } $table->fields());
    unless ($sucess)
    {
        # TODO: Raise an exception.
        cluck (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                      $search_obj_sql,
                      (map { lc("\%$string\%") } $table->fields()),
                      $dbh->err,
                      $dbh->errstr));
        return undef;
    }

    my %row = ( _dbh   => $dbh,
                _table => $table);
    $search_obj_sth->bind_columns(map { \$row{$_} } $table->primaryKeys(), $table->fields());

    my @rows;
    while ($search_obj_sth->fetch)
    {
        my (%newRow) = (%row);
        push @rows, bless (\%newRow, $class);
    }
    $search_obj_sth->finish;

    return wantarray ? @rows : $rows[0];
}
# /* searchByString */ }}} 

# /* _valueMap */ {{{ 
sub _valueMap
{
    my $self = shift;

    my $fName = shift;
    my $value = shift;

    if (!$value)
    {
        return undef;
    }
    return $value;
}
# /* _valueMap */ }}} 

# /* insert */ {{{
=pod

=head2 Object Methods

=over 4

=item $row->insert();

Once constructed, the row can be inserted into the database. If the row cannot be inserted
into the database, then undef is returned (You should then check L<validationError()>, and
then use L<getValidationError()> on each field to see the reason why the row could not be
inserted.

=cut
sub insert
{
    my $self = shift;

    unless ($self->validate())
    {
        # TODO: Raise an exception.
        return undef;
    }

    my $new_sql = sprintf("INSERT INTO %s ( %s ) VALUES ( %s )", $self->{'_table'}->name(),
                                                                 join (', ', $self->{'_table'}->fields()),
                                                                 join (', ', map { '?' } $self->{'_table'}->fields()));

    my $new_obj_sth = $self->{'_dbh'}->prepare_cached($new_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $new_sql, $self->{'_dbh'}->err, $self->{'_dbh'}->errstr));

    my @values = map { $self->_valueMap($_, $self->{$_}) } $self->{'_table'}->fields();

    if ($self->{'_dbh'}->can('pg_savepoint') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
    {
        $self->{'_dbh'}->pg_savepoint("pre_insert"); # Create a save-point in the transaction
    }
    $new_obj_sth->execute(@values) or
    do {
        if ($self->_catchDupeKeyError())
        {
            if ($self->{'_dbh'}->can('pg_rollback_to') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
            {
                $self->{'_dbh'}->pg_rollback_to("pre_insert"); # Go back to before the failed execute()
            }
            return undef;
        }
        # TODO: Raise an exception.
        confess (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                      $new_sql,
                      join(',', @values),
                      $self->{'_dbh'}->err,
                      $self->{'_dbh'}->errstr));
    };
    if ($self->{'_dbh'}->can('pg_release') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
    {
        $self->{'_dbh'}->pg_release("pre_insert");
    }

    # WARNING: This assumes that the first primary key field is the one with the serial column.
    # In most cases it is, but this wont work if it isnt.

    my $seqName = sprintf("%s_%s_seq", $self->{'_table'}->name(), ($self->{'_table'}->primaryKeys())[0]);
    my $lastIdSql = "SELECT CURRVAL(?)";
    my $lastIdSth = $self->{'_dbh'}->prepare_cached($lastIdSql, {pg_prepare_now => 1}, 3)
      or confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $lastIdSql, $self->{'_dbh'}->err, $self->{'_dbh'}->errstr));

    $lastIdSth->execute($seqName);
    my $newId = $lastIdSth->fetchall_arrayref()->[0]->[0];

    $self->{($self->{'_table'}->primaryKeys())[0]} = $newId;
    return $newId;
}
# /* insert */ }}}

# /* update */ {{{
=pod

=item $row->update();

If any changes are made to the values of a row, then when the row gets DESTORY'd,
the changes will automatically be saved back to the database. However, you may wish
explicitly call update() for two reasons: You may want the changes saved to the datbase
before the row object goes out of scope, and (more importantly) you should check the
return value of the call to update() to catch any invalid values.

If the row could not be updated in the database, then undef is returned (You should then
check L<validationError()>, and then use L<getValidationError()> on each field to see
the reason why the row could not be inserted.

=cut
sub update
{
    my $self = shift;

    unless ($self->validate())
    {
        # TODO: Raise an exception.
        return undef;
    }

    my $update_sql = sprintf("UPDATE %s SET %s WHERE %s",
                             $self->{'_table'}->name(),
                             join(', ',     map { "$_ = ?" } $self->{'_table'}->fields()),
                             join(' AND ', map { "$_ = ?" } $self->{'_table'}->primaryKeys()));

    my $update_sth = $self->{'_dbh'}->prepare_cached($update_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $update_sql, $self->{'_dbh'}->err, $self->{'_dbh'}->errstr));

    my @values = map { $self->_valueMap($_, $self->{$_}) } $self->{'_table'}->fields(), $self->{'_table'}->primaryKeys();
    if ($self->{'_dbh'}->can('pg_savepoint') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
    {
        $self->{'_dbh'}->pg_savepoint("pre_update"); # Create a save-point in the transaction
    }
    $update_sth->execute(@values) or
    do
    {
        if ($self->_catchDupeKeyError())
        {
            if ($self->{'_dbh'}->can('pg_rollback_to') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
            {
                $self->{'_dbh'}->pg_rollback_to("pre_update"); # Go back to before the failed execute()
            }
            return undef;
        }
        # TODO: Raise an exception.
        confess (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                          $update_sql,
                          join(', ', @values),
                          $self->{'_dbh'}->err,
                          $self->{'_dbh'}->errstr));
    };
    if ($self->{'_dbh'}->can('pg_release') && $self->{'_dbh'}->{private_dbdpg}{version} >= 80000)
    {
        $self->{'_dbh'}->pg_release("pre_update");
    }
    delete($self->{'_modified'});
    return 1;
}
# /* update */ }}}

# /* delete */ {{{
=pod

=item $row->delete();

This method deletes the row from the database, and marks it as deleted so that
futher access to the object can be made. You can still use a deleted object
to L<construct()> a new one though.

=cut
sub delete
{
    my $self  = shift;

    if ($self->{'_deleted'})
    {
        cluck("Attempt to delete an object twice");
        return undef;
    }

    my $delete_sql = sprintf("DELETE FROM %s WHERE %s",
                             $self->{'_table'}->name(),
                             join(' AND ', map { "$_ = ?" } $self->{'_table'}->primaryKeys()));
    my $delete_sth = $self->{'_dbh'}->prepare_cached($delete_sql, {pg_prepare_now => 1}, 3) or
      confess (sprintf("Could not prepare_cached(%s): Error Code %d (%s)", $delete_sql, $self->{'_dbh'}->err, $self->{'_dbh'}->errstr));

    $delete_sth->execute(map {$self->{$_}} $self->{'_table'}->primaryKeys()) or
    do {
            # TODO: Raise an exception.
            cluck (sprintf("Could not execute(%s)\n(%s)\n Error Code %d (%s)",
                          $delete_sql,
                          join (', ', map {$self->{$_}} $self->{'_table'}->primaryKeys()),
                          $self->{'_dbh'}->err,
                          $self->{'_dbh'}->errstr));
            return undef;
    };

    delete($self->{'_modified'}); # Prevent update attempts
    $self->{'_deleted'}  = 1;     # Prevent further object access

    return 1;
}
# /* delete */ }}}

# /* _catchDupeKeyError */ {{{
sub _catchDupeKeyError
{
    my $self = shift;
    my $errorString = $self->{'_dbh'}->errstr;

    my $tableName = $self->{'_table'}->name();
    # TODO: This error string is postresql specific. Perhaps I should create a DB::Table::Row::Pg module instead?
    # For now, people can just overload this method.
    if ($errorString =~ /^ERROR:\s+duplicate key violates unique constraint "$tableName\_(.+?)\_key"$/)
    {
        my $dupeField = $1;
        my $tableIsVowel = ''; my $fieldIsVowel = '';
        $tableIsVowel = 'n' if (lc($self->{'_table'}->desc()->[0]) =~ /^[aeiou]/);
        $fieldIsVowel = 'n' if (lc($self->{'_table'}->field($dupeField)->{'desc'}) =~ /^[aeiou]/);

        my $fieldDesc = $self->{'_table'}->{'field'}->{$dupeField}->{'desc'};
        $self->{'_validation'}->{$dupeField} = sprintf("There is already a%s %s with a%s %s of '%s'. %s must be unique",
                                                       $tableIsVowel, lc($self->{'_table'}->desc()->[0]),
                                                       $fieldIsVowel, lc($fieldDesc),
                                                       $self->$dupeField, ucfirst(lc($fieldDesc)));
        $self->{'_validationError'} = 1;
        return 1;
    }
    return undef;
}
# /* _catchDupeKeyError }}}

# /* getFKey */ {{{
=pod

=item my $foreignRow = $row->getFKey($foreignKeyField);

Where $foreignKeyField in $row references a row in another table,
this method can be used to fetch the referenced row.

=cut
sub getFKey
{
    my $self = shift;

    my $fkeyName  = shift;
    my $fkey      = $self->{'_table'}->field($fkeyName)->{'fkey'} || do { cluck("Cannot get fkey"); return undef };

    my $fTable = $self->getFTable($fkeyName);
    return $fTable->getRowByPKey($self->$fkeyName());
}
# /* getFKey */ }}}

# /* getFTable */ {{{ 
=pod

=item my $foreignTable = $row->getFTable($foreignKeyField);

Where $foreignKeyField in $row references a row in another table,
this method can be used to return the referenced table object.

=cut
sub getFTable
{
    my $self = shift;

    my $fieldName = shift;

    my $className = sprintf("DB::Table::%s", ucfirst(lc($self->{'_table'}->field($fieldName)->{'fkey'}->{'table'})));
    if ($className->can('open'))
    {
        return $className->open($self->{'_dbh'});
    }
    return DB::Table->open($self->{'_dbh'}, $self->{'_table'}->field($fieldName)->{'fkey'}->{'table'});
}
# /* getFTable */ }}} 

# /* getValue */ {{{ 
=pod

=item my $value = $row->getValue($fieldName);

This method is used to get the value of the field/column specified by $fieldName.

fieldName's are also autoloaded, so you can also say:

    my $value = $row->$fieldName();

=cut
sub getValue
{
    my $self = shift;

    my $fieldName = shift;

    if (exists($self->{'_deleted'}))
    {
        confess("Cannot access a deleted object");
    }

    unless ($self->{'_table'}->field($fieldName) or exists ($self->{$fieldName}))
    {
        confess("Field $fieldName does not exist in table/object - possible typo???");
    }

    unless(exists($self->{'_table'}->field($fieldName)->{'read'}))
    {
        confess("You cannot read field $fieldName")
    }
    return $self->{$fieldName};
}
# /* getValue */ }}} 

# /* setValue */ {{{ 
=pod

=item my $oldValue = $row->setValue($fieldName, $newValue);

This method is used to set a new value for the field specified by $fieldName.

The old value is returned.

fieldName's are also autoloaded, so you can also say:

    my $oldValue = $row->$fieldName($newValue);

=cut
sub setValue
{
    my $self = shift;

    my $fieldName = shift;
    my $newValue  = shift;

    if (exists($self->{'_deleted'}))
    {
        confess("Cannot access a deleted object");
    }

    unless ($self->{'_table'}->field($fieldName) or exists ($self->{$fieldName}))
    {
        confess("Field $fieldName does not exist in table/object - possible typo???");
    }

    unless(exists($self->{'_table'}->field($fieldName)->{'write'}))
    {
        confess("You cannot update field $fieldName")
    }

    my $oldValue = $self->{$fieldName};
    $self->{$fieldName} = $newValue;
    $self->{'_modified'} = 1;
    return $oldValue;
}
# /* setValue */ }}} 

# /* AUTOLOAD */ {{{
# The accessor methods to this object are auto-loaded...
sub AUTOLOAD
{
    my $self = shift;
    my $name = our $AUTOLOAD;

    # make sure we were called in an object-oriented manor
    # (class-methods are not auto-loaded)
    confess("$self is not an object ($name)") unless (ref($self));

    my $table = $self->{'_table'};

    my ($field) = ($name =~ /::([a-zA-Z0-9_]+)$/);

    if (@_)
    {
        return $self->setValue($field, @_);
    }
    return $self->getValue($field);
}
# /* AUTOLOAD */ }}}

# /* DESTROY */ {{{
sub DESTROY
{
    # If we have been modified, write the changes back to the DB.
    my $self = shift;

    if (exists ($self->{'_modified'}) && !exists($self->{'_deleted'}))
    {
        unless ($self->update())
        {
            confess("Row destroyed but could not be updated. You should call to update() explicitly to catch any validation errors");
        }
    }
}
# /* DESTROY */ }}}

# /* validationError */ {{{ 
=pod

=item my $didError = $row->validationError();

This method returns true if an insert() or update() failed
because of a validation error (false otherwise).

If this method returns true, you should iterate through each
field and call L<getValidationError()> to see which field failed
validation, and why.

=cut
sub validationError
{
    my $self = shift;

    return $self->{'_validationError'};
}
# /* validationError */ }}} 

# /* getValidationError */ {{{ 
=pod

=item my $errorMsg = $row->getValidationError($fieldName);

If an L<insert()> or L<update()> failed because of a validation error (check
with L<validationError> then you should iterate through each field and call
getValidationError to get the error message associated with each field. Fields
without an error message passed validation, hence undef is returned.

=cut
sub getValidationError
{
    my $self = shift;

    my $fieldName = shift || return undef;

    return $self->{'_validation'}->{$fieldName};
}
# /* getValidationError */ }}} 

# /* validate */ {{{ 
=pod

=item my $didValidate = $row->validate();

Validation is automatically performed when ever needed (before the row is
inserted or updated in the database) and as such you probably wont need to
call this explicitly, however, it is here in case you do.

If all values are considered legal, then true is returned, undef otherwise.

The exception is that validation is performed in such a way that the database
never has to read/write any rows in the database, and as such duplicate key
checking is not performed here. Instead, if validation passes, the record will
be then be inserted/updated and if this fails because of a duplicate key then
this is trapped and undef is then returned by the insert/update method (After
setting the various validation-related error flags).

=back

=cut
sub validate
{
    my $self = shift;

    our $textFields = {'character varying' => 1,
                       'character'         => 1};
                       # We dont include 'text' here because it is not length-limited.

    my @constraints;
    my $isValid = 1;
    foreach my $fieldName ($self->{'_table'}->fields)
    {
        my $field = $self->{'_table'}->field($fieldName);

        if ($textFields->{$field->{'type'}})
        {
            if (length($self->$fieldName) > $field->{'length'})
            {
                $self->{'_validation'}->{$fieldName} = "Value is too long (must be <= " . $field->{'length'} . ")";
                $isValid = 0;
            }
        }

        my $regex = $field->{'validate'}->{'regex'};
        eval {
            unless ($self->$fieldName =~ /$regex/)
            {
                $self->{'_validation'}->{$fieldName} = $field->{'validate'}->{'error'} || "regular expression $regex failed";
                $isValid = 0;
            }
        };
        if ($@)
        {
             confess("Failed to compile regular expression for $fieldName: $@");
        }
        if (!$field->{'nullable'} && !$self->$fieldName)
        {
            $self->{'_validation'}->{$fieldName} = $field->{'desc'} . " must not be empty";
            $isValid = 0;
        }
        if ($field->{'constraint'})
        {
            push @constraints, $field;
        }
    }
    unless ($isValid)
    {
        $self->{'_validationError'} = 1;
        return undef;
    }
    my $fieldMap = join('|', $self->{'_table'}->fields());
    my @checks;
    CONSTRAINT:
    foreach my $c (@constraints)
    {
        my $text = $c->{'constraint'};
        my @refs = ($text =~ /\b($fieldMap)\b/g);
        foreach my $ref (@refs)
        {
            next CONSTRAINT unless ($self->$ref);
            my $type = $self->{'_table'}->field($ref)->{'type'};
            my $value = $self->{'_dbh'}->quote($self->$ref);
            my $cast = "$value\:\:$type";
            $text =~ s/\b$ref\b/$cast/ge;
        }
        my $check = sprintf("CASE WHEN %s THEN 1 ELSE 0 END AS %s", $text, $c->{'name'});
        push @checks, $check;
    }

    # If there are no constraints, then return true
    unless (scalar(@checks) >= 1)
    {
        return 1;
    }

    my $validateSql = sprintf("SELECT %s", join (', ', @checks));
    my $validateSth = $self->{'_dbh'}->prepare($validateSql) or
          confess (sprintf("Could not prepare(%s): Error Code %d (%s)", $validateSql, $self->{'_dbh'}->err, $self->{'_dbh'}->errstr));
    $validateSth->execute() or
    do {
        # TODO: Raise an exception.
        cluck (sprintf("Could not execute(%s)\nError Code %d (%s)",
                      $validateSql,
                      $self->{'_dbh'}->err,
                      $self->{'_dbh'}->errstr));
        return undef;
    };
    my $valid = $validateSth->fetchrow_hashref();
    foreach my $field (keys %{$valid})
    {
        unless ($valid->{$field})
        {
            $self->{'_validation'}->{$field} = sprintf("constraint %s failed", $self->{'_table'}->field($field)->{'constraint'});
            $self->{'_validationError'} = 1;
            $isValid = undef;
        }
    }
    delete($self->{'_validationError'}) if ($isValid);
    return $isValid;
}
# /* validate */ }}} 

=pod

=head1 AUTHOR

Bradley Kite <bradley-cpan@kitefamily.co.uk>

If you wish to email me, then please remove the '-cpan' part
of my email address as anything addressed to 'bradley-cpan'
is assumed to be spam and is not read.

=head1 SEE ALSO

L<DB::Table>, L<DBI>, L<perl>

=cut

1;

