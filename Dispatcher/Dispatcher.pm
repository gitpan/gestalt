

package Apache::Request::Dispatcher;

use strict;
use DBI;
use Template;
use AppConfig;
#use Exception qw(:all);
use Apache2;
use Apache::Const qw(:common :methods :http);
use POSIX qw(strftime);
use Carp qw(cluck);
use Apache::Session::Postgres;
use Apache::Session::MySQL;

use Data::Dumper;

# TODO: Need to change these to Apache::Request (libapreq)
use CGI;
use CGI::Cookie;

our @ISA;

# /* handler */ {{{
sub handler
{
    my $r = shift;

    # Validate the URI
    my $uri = $r->uri;
    if ($uri !~ /^[A-Za-z0-9_\/]+$/)
    {
        warn("URI is not taint-safe - declining request");
        return DECLINED;
    }

    my $self = init($r);

    # Start parsing the URI
    my @bits = split(/\/+/, $uri);

    # Drop first 2 bits
    shift @bits;
    shift @bits;

    my $webPrefix = 'Apache::Request::Controller';
    my $method    = pop @bits;
    my $pkgName   = join('::', $webPrefix, @bits);

    # Show the "Index" page of the given component.
    if ($pkgName eq $webPrefix)
    {
        $pkgName .= '::' . $method;
        $method   = '';
    }

    if ($pkgName eq 'Apache::Request::Controller::' || $pkgName eq 'Apache::Request::Controller')
    {
        if ($self->{'cfg'}->defaultController)
        {
            unless ($uri =~ /\/$/)
            {
                $uri .= '/';
            }
            $uri .= $self->{'cfg'}->defaultController;
            $r->uri($uri);
            $r->headers_out->set(Location => $uri);
            return HTTP_MOVED_TEMPORARILY;
        }
    }

#    my $ret = try {
        unshift @ISA, ($pkgName);
        my $return;
        eval {
            if ($method eq '')
            {
                unless ($uri =~ /\/$/)
                {
                    $uri .= '/';
                }
                if ($self->can('__index'))
                {
                    $uri .= $self->__index();
                    $r->uri($uri);
                    $r->headers_out->set(Location => $uri);
                    $return  = HTTP_MOVED_TEMPORARILY;
                }
                else
                {
                    warn("Cannot figure out the default method of $pkgName. Please write an __index() method which returns it");
                    $return = DECLINED;
                }
            }
            elsif ($self->can($method))
            {
                if ($self->can('__cache'))
                {
                    $r->no_cache(($self->__cache() ? 0 : 1));
                }
                else
                {
                    $r->no_cache(1);
                }
                $return = $self->$method();
                if ($return == OK || $return == HTTP_MOVED_TEMPORARILY)
                {
                    $self->{'session'}->{'_mtime'} = time();
                    $self->{'dbh'}->commit();
                }
            }
            else
            {
                warn("Cannot find $pkgName->$method, declining request");
                $return = DECLINED;
            }
        };
        if ($@)
        {
            my $err = sprintf("Cannot dispatch to %s->%s (%s)",
                               $pkgName, $method, $@);
            warn($err);
            # Exception->new('other')->raise($err);
            $self->{'dbh'}->rollback;
            return HTTP_INTERNAL_SERVER_ERROR;
        }
        if ($return != OK && $return != HTTP_MOVED_TEMPORARILY)
        {
            $self->{'dbh'}->rollback;
        }
        return $return;
#    }
#    when 'template',
#    except
#    {
#        # If a template error occurs, then the http header etc. would
#        # have already have been sent.
#        my $err = shift;
#        $err->confess;
#        $self->{'template'}->process('error.tt2'. {ERROR => $err->stringify})
#          or do { print $err->stringify };
#        return OK;
#    }
#    when 'not_found',
#    except
#    {
#        my $err = shift;
#        $err->confess;
#        return DECLINED;
#    }
#    when 'other',
#    except
#    {
#        my $err = shift;
#        $err->confess;
#        return HTTP_INTERNAL_SERVER_ERROR;
#    }
#    finally
#    {
#        my $err = shift; 
#        my $retCode = shift;

#        if ($err)
#        {
#            $self->{'dbh'}->rollback;
#        }
#        else
#        {
#            $self->{'dbh'}->commit;
#        }
#        return $retCode;
#    };
#
#    return $ret;
}
# /* handler */ }}}

# /* init */ {{{
sub init
{
    my $r = shift;

    # Do some initial setup config.

    @ISA = ();

    my $q = new CGI;

    # TODO: Perhaps cache the config files using the key ($ENV{'DispatcherConf'}) into a
    #       global hash
    my ($cfg, $dbh, $template);
    unless ($cfg)
    {
        $cfg = AppConfig->new(qw(db_dsn=s db_username=s db_password=s
                                 templatePath=s defaultController=s
                                 useSessions=s
                                 session_dsn=s session_username=s session_password=s));
        $cfg->file($ENV{'DispatcherConf'}) || die "Could not open config: $ENV{DispatcherConf}: $!";
    }

    if ($cfg->db_dsn)
    {
        $dbh = DBI->connect($cfg->db_dsn, $cfg->db_username, $cfg->db_password,
                            {AutoCommit => 0,
                             RaiseError => 0});
        unless ($dbh)
        {
            confess(sprintf("Could not connect to database %s: %s",
                            $cfg->db_dsn,
                            $DBI::errstr));
        }
    }

    my %session;
    if ($cfg->useSessions)
    {
        my $cookies = CGI::Cookie->fetch($r) || {};
        my $cookie  = $cookies->{'session_id'};

        if ($cookie)
        {
            my $cookieValue = $cookie->value;
            tie %session, $cfg->useSessions, $cookieValue, {Handle => $dbh,
                                                            Commit => 1};
        }
        else
        {
            tie %session, $cfg->useSessions, undef, {Handle => $dbh,
                                                     Commit => 1};
        }
        # TODO: Add some extra stuff to the config file to determine cookie
        #       options, such as expire time.
        $cookie = $q->cookie('-name'    => 'session_id',
                             '-value'   => $session{'_session_id'},
                             #'-expires' => '+1d', Per-Session is all thats needed.
                             '-path'    => '/' . $ENV{'APP_NAME'} . '/',
                             '-domain'  => $r->hostname,
                             '-secure'  => 0);
        $r->headers_out->set('Set-Cookie' => $cookie->as_string);
    }

    my $templatePath = $cfg->templatePath || '/data/templates';
    $template ||= new Template(INCLUDE_PATH => $templatePath,
                               RECURSION    => 1,
                               PRE_DEFINE   => { DisplayNumber   => \&T_DisplayNumber,
                                                 DisplayDate     => \&T_DisplayDate,
                                                 DisplayTime     => \&T_DisplayTime,
                                                 DisplayDateTime => \&T_DisplayDateTime,
                                                 DisplayDuration => \&T_DisplayDuration,
                                                 APP_NAME        => $ENV{'APP_NAME'},
                                                 REQUEST         => $r});
    my $self = {request  => $r,
                dbh      => $dbh,
                cfg      => $cfg,
                template => $template,
                apr      => $q,
                session  => \%session};
    bless ($self, 'Apache::Request::Dispatcher');

    return $self;
}
# /* init */ }}}

# /* Template Display Functions */ {{{
sub T_DisplayNumber
{
    my $number = reverse(shift);
    $number =~ s/(\d\d\d)(?!$)/$1\,/g;
    return scalar(reverse($number));
}

sub T_DisplayDateTime
{
    my $time = shift;

    return strftime('%a %d %B %T %Y', gmtime($time));
}

sub T_DisplayTime
{
    my $time   = shift;
    my $format = shift || '%a %d %B %Y';

    return strftime($format, gmtime($time));
}

sub T_DisplayDate
{
    my $time   = shift;
    my $format = shift || '%a %d %B %Y';

    return strftime($format, gmtime($time));
}

sub T_DisplayDuration
{
    my $duration = shift; # number of seconds

    my @bits = ({ NAME => 'Seconds',
                  NEXT => 60},
                { NAME => 'Minutes',
                  NEXT => 60 },
                { NAME => 'Hours',
                  NEXT => '24' },
                { NAME => 'Days',
                  NEXT => 7 },
                { NAME => 'Weeks' });
    my @results;
    do
    {
        my $remainder = ($duration % $bits[0]->{'NEXT'});
        unshift @results, sprintf("%d %s", $remainder,
                                        $bits[0]->{'NAME'}) if ($remainder > 0);
        $duration -= $remainder;
        $duration /= $bits[0]->{'NEXT'};
        shift @bits;
    }
    while (defined ($bits[0]) && defined ($bits[0]->{'NEXT'}));

    return join(' ', @results);
}
# /* Template Display Functions */ }}}

1;

