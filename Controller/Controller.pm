
package Apache::Request::Controller;

use strict;
use Apache::Const qw(:common :methods :http);
#use Exception qw(:all);

use Carp qw(cluck);
use vars qw(@ISA);
use Paginator;

# These are the generic controller actions. The objects
# that these actions are performed on are passed in
# by things that inherit from us

# /* create */ {{{
sub create
{
    my $self  = shift;
    my $table = $self->__openTable();

    my $obj;
    foreach my $field ($table->fields)
    {
        $obj->{$field} = $self->{'apr'}->param($field);
    }
    my $row = $table->constructRow($obj);
    if (defined($self->{'apr'}->param('action')) && lc($self->{'apr'}->param('action')) eq 'create')
    {
        if ($row->insert())
        {
            return $self->list();
        }
        # validation failed - redisplay the form.
    }
    $self->{'request'}->status(HTTP_OK);
    $self->{'request'}->content_type('text/html');

    $self->{'template'}->process(ucfirst(lc($table->name())) . "/create.tt2",
                                 {TABLE => $table,
                                  ROW   => $row}) or do {  print $self->{'template'}->error } ;
    return OK;
}
# /* create */ }}}

# /* _get */ {{{
sub _get
{
    my $self = shift;
    my $table = shift;
    
    my @pkeys;
    foreach my $pkey ($table->primaryKeys)
    {
        push @pkeys, $self->{'apr'}->param($pkey);
    }
    return $table->getRowByPKey(@pkeys);
}
# /* _get */ }}}

# /* show */ {{{
sub show
{
    my $self       = shift;
    my $table      = $self->__openTable();

    my $row = $self->_get($table);

    $self->{'request'}->status(HTTP_OK);
    $self->{'request'}->content_type('text/html');
    $self->{'template'}->process(ucfirst(lc($table->name())) . "/show.tt2",
                                 {TABLE => $table,
                                  ROW   => $row}) or do { print $self->{'template'}->error };
    return OK;
}
# /* show */ }}}

# /* edit */ {{{
sub edit
{
    my $self  = shift;
    my $table = $self->__openTable();
    my $row = $self->_get($table);

    $self->{'request'}->status(HTTP_OK);
    $self->{'request'}->content_type('text/html');
    $self->{'template'}->process(ucfirst(lc($table->name())) . "/edit.tt2",
                                 {TABLE => $table,
                                  ROW   => $row}) or do { print $self->{'template'}->error };
    return OK;
}
# /* edit */ }}}

# /* update */ {{{
sub update
{
    my $self       = shift;
    my $table      = $self->__openTable();

    my $row = $self->_get($table);
    foreach my $field ($table->fields)
    {
        $row->$field($self->{'apr'}->param($field));
    }
    unless ($row->update())
    {
        $self->{'request'}->status(HTTP_OK);
        $self->{'request'}->content_type('text/html');
        $self->{'template'}->process(ucfirst(lc($table->name())) . "/edit.tt2",
                                     {TABLE => $table,
                                      ROW   => $row}) or do { print $self->{'template'}->error };
        return OK;
    }
    return $self->list;
}
# /* update */ }}}

# /* delete */ {{{
sub delete
{
    my $self       = shift;
    my $table      = $self->__openTable();

    my $row = $self->_get($table) || return $self->list;
    $row->delete();

    return $self->list;
}
# /* delete */ }}}

# /* list */ {{{
sub list
{
    my $self       = shift;
    my $table      = $self->__openTable();

    my $pageStart = $self->{'apr'}->param('pageStart');
    my $pageSize  = $self->{'apr'}->param('pageSize');

    if ($pageStart eq '')
    {
        $pageStart = $self->{'session'}->{$table->name}->{'pageStart'} || 0;
    }

    if ($pageSize eq '')
    {
        $pageSize = $self->{'session'}->{$table->name}->{'pageSize'} || 10;
    }

    $self->{'session'}->{$table->name}->{'pageStart'} = $pageStart;
    $self->{'session'}->{$table->name}->{'pageSize'}  = $pageSize;

    my @rows = $table->getRowsByPKey();
    my $book = Paginator->new({ pageSize  => $pageSize,
                                pageStart => $pageStart}, \@rows);

    $self->{'request'}->status(HTTP_OK);
    $self->{'request'}->content_type('text/html');
    $self->{'template'}->process(ucfirst(lc($table->name())) . "/list.tt2",
                                 {TABLE => $table,
                                  ROWS  => \@rows,
                                  BOOK  => $book}) or do { print $self->{'template'}->error };
    return OK;
}
# /* list */ }}}

# /* search */ {{{ 
sub search
{
    my $self = shift;

    my $table = $self->__openTable();
    my $string = $self->{'apr'}->param('pattern') || '';
    unless ($string)
    {
        return $self->list;
    }

    my $pageStart = $self->{'apr'}->param('pageStart');
    my $pageSize  = $self->{'apr'}->param('pageSize');

    if ($pageStart eq '')
    {
        $pageStart = $self->{'session'}->{$table->name}->{'pageStart'} || 0;
    }

    if ($pageSize eq '')
    {
        $pageSize = $self->{'session'}->{$table->name}->{'pageSize'} || 10;
    }

    $self->{'session'}->{$table->name}->{'pageStart'} = $pageStart;
    $self->{'session'}->{$table->name}->{'pageSize'}  = $pageSize;

    my @rows = $table->searchRowsByString($string);
    my $book = Paginator->new({ pageSize  => $pageSize,
                                pageStart => $pageStart}, \@rows);
    $self->{'request'}->status(HTTP_OK);
    $self->{'request'}->content_type('text/html');
    $self->{'template'}->process(ucfirst(lc($table->name())) . "/list.tt2",
                                 {TABLE   => $table,
                                  ROWS    => \@rows,
                                  BOOK    => $book,
                                  PATTERN => $string}) or do { print $self->{'template'}->error };
    return OK;
}
# /* search */ }}} 

1;
