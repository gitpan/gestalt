
package Paginator;

use strict;
use Carp qw(cluck confess);

# /* new */ {{{
sub new
{
    my $ref   = shift;
    my $class = ref($ref) || $ref;

    my $pageOptions        = shift;
    my $pageObjects        = shift;

    my $self = { pageObjects => $pageObjects,
                 pageSize    => $pageOptions->{'pageSize'},
                 pageStart   => $pageOptions->{'pageStart'}};

    return bless ($self, $class);
}
# /* new */ }}}

# /* pageSize */ {{{
sub pageSize
{
    my $self = shift;
    my $newSize = shift;
    if ($newSize)
    {
        my $oldSize = $self->{'pageSize'};
        $self->{'pageSize'} = $newSize;
        return $oldSize;
    }
    return $self->{'pageSize'};
}
# /* pageSize */ }}}

# /* pageStart */ {{{
sub pageStart
{
    my $self     = shift;
    my $newStart = shift;
    if ($newStart)
    {
        my $oldStart = $self->{'pageStart'};
        $self->{'pageStart'} = $newStart;
        return $oldStart;
    }
    return $self->{'pageStart'} || 0;
}
# /* pageStart */ }}}

# /* numPages */ {{{ 
sub numPages
{
    my $self = shift;

    if ($self->{'pageSize'} == 0)
    {
        return 1;
    }

    my $numObjects = scalar(@{$self->{'pageObjects'}});
    my $numPages   = int($numObjects / $self->{'pageSize'});
    my $remainder  = $numObjects % $self->{'pageSize'};

    return $remainder ? $numPages + 1 : $numPages;
}
# /* numPages */ }}} 

# /* numObjects */ {{{ 
sub numObjects
{
    my $self = shift;

    return scalar(@{$self->{'pageObjects'}});
}
# /* numObjects */ }}} 

# /* getObjects */ {{{ 
sub getObjects
{
    my $self = shift;

    if ($self->{'pageSize'} == 0)
    {
        return @{$self->{'pageObjects'}};
    }

    # This is anoying. splice actually removes the elements instead of just returning them.
    my @elements = splice(@{$self->{'pageObjects'}}, $self->{'pageStart'}, $self->{'pageSize'});
    # Need to put them back:
    splice(@{$self->{'pageObjects'}}, $self->{'pageStart'}, 0, @elements);
    return @elements;
}
# /* getObjects */ }}} 

# /* nextPage */ {{{ 
sub nextPage
{
    my $self = shift;

    my $nextPageStart = $self->{'pageStart'} + $self->{'pageSize'};
    if ($nextPageStart < $self->numPages * $self->{'pageSize'})
    {
        return $nextPageStart;
    }
    return ($self->numPages - 1) * $self->{'pageSize'};
}
# /* nextPage */ }}} 

# /* previousPage */ {{{ 
sub previousPage
{
    my $self = shift;

    my $previousPageStart = $self->{'pageStart'} - $self->{'pageSize'};
    if ($previousPageStart >= 0)
    {
        return $previousPageStart;
    }
    return 0;
}
# /* previousPage */ }}} 

# /* currentPage */ {{{ 
sub currentPage
{
    my $self = shift;

    if ($self->{'pageSize'} == 0)
    {
        return 1;
    }

    my $newPage = shift;
    if (defined ($newPage))
    {
        my $oldPage = ($self->{'pageStart'} / $self->{'pageSize'}) + 1;
        $self->{'pageStart'} = $newPage * $self->{'pageSize'};
        return $oldPage;
    }
    return ($self->{'pageStart'} / $self->{'pageSize'}) + 1;
}
# /* currentPage */ }}} 

# /* firstObject */ {{{ 
sub firstObject
{
    my $self = shift;

    if ($self->{'pageSize'} == 0)
    {
        return 1;
    }
    return $self->{'pageStart'} + 1;
}
# /* firstObject */ }}} 

# /* lastObject */ {{{ 
sub lastObject
{
    my $self = shift;

    if ($self->{'pageSize'} == 0)
    {
        return scalar(@{$self->{'pageObjects'}});
    }

    my $lastObject = $self->{'pageStart'} + $self->{'pageSize'};
    my $numObjects = $self->numObjects;
    return $lastObject < $numObjects ? $lastObject : $numObjects;
}
# /* lastObject */ }}} 

1;
