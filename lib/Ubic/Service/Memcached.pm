package Ubic::Service::Memcached;

use strict;
use warnings;

# ABSTRACT: memcached as ubic service

=head1 SYNOPSIS

    use Ubic::Service::Memcached;

    return Ubic::Service::Memcached->new({
        port => 1234,
        pidfile => "/var/run/my-memcached.pid",
        maxsize => 500,
    });

=head1 DESCRIPTION

This module allows you to run memcached using L<Ubic>.

Its status method tries to store C<Ubic::Service::Memcached-testkey> key in memcached to check that service is running.

=head1 METHODS

=over

=cut

use parent qw(Ubic::Service::Skeleton);
use Ubic::Daemon qw(:all);
use Ubic::Result qw(result);
use Cache::Memcached;
use Carp;

use Params::Validate qw(:all);

use Morpheus '/module/Ubic/Service/Memcached' => [
    'pid_dir' => '?$PID_DIR',
];

=item B<< new($params) >>

Constructor.

Parameters:

=over

=item I<port>

Integer port number.

=item I<pidfile>

Full path to pidfile. Pidfile will be managed by C<Ubic::Daemon>.

You can skip this parameter if you have C</module/Ubic/Service/Memcached/pid_dir> morpheus option configured. In this case pidfile will be located in that directory and have name C<$port.pid>.

=item I<maxsize>

Max memcached memory size in megabytes. Default is 640MB.

=item I<verbose>

Enable memcached logging.

C<verbose=1> turns on basic error and warning logs (i.e. it sets C<-v> switch),

C<verbose=2> turns on more detailed logging (i.e. it sets C<-vv> switch).

=item I<logfile>

If specified, memcached will be configured to write logs to given file.

=item I<ubic_log>

Optional log with ubic-specific messages.

=item I<max_connections>

Number of max simultaneous connections (C<-c> memcached option).

=item I<other_argv>

Any argv parameters to memcached binary which are not covered by this module's API.

=item I<user>

=item I<group>

As usual, you can specify custom user and group values. Default is C<root:root>.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        binary => { type => SCALAR, regex => qr/^.*\/memcached$/, default => '/usr/bin/memcached' },
        port => { type => SCALAR, regex => qr/^\d+$/ },
        pidfile => { type => SCALAR, optional => 1 },
        maxsize => { type => SCALAR, regex => qr/^\d+$/, default => 640 },
        verbose => { type => SCALAR, optional => 1 },
        max_connections => { type => SCALAR, optional => 1 },
        logfile => { type => SCALAR, optional => 1 },
        ubic_log => { type => SCALAR, optional => 1 },
        user => { type => SCALAR, default => 'root' },
        group => { type => SCALAR, optional => 1},
        ulimit => { type => HASHREF, optional => 1 },
        other_argv => { type => SCALAR, optional => 1 },
    });

    if ($params->{ulimit}) {
        # load BSD::Resource lazily, but fail fast if we're asked for it
        eval "require BSD::Resource";
        if ($@) {
            die "BSD::Resource is not installed";
        }
        if (BSD::Resource->VERSION < 1.29) {
            # 1.29 supports string names for resources
            die "BSD::Resource >= 1.29 required";
        }
    }

    if (not defined $params->{pidfile}) {
        unless (defined $PID_DIR) {
            croak "pidfile parameter not defined, define it or set /module/Ubic/Service/Memcached/pid_dir configuration option";
        }
        $params->{pidfile} = "$PID_DIR/$params->{port}.pid";
    }

    return bless $params => $class;
}

sub start_impl {
    my $self = shift;

    my $params = [];

    push @$params, "-u $self->{user}" if $self->{user} eq 'root';
    push @$params, "-p $self->{port}";
    push @$params, "-m $self->{maxsize}";
    push @$params, "-c $self->{max_connections}" if defined $self->{max_connections};

    my $verbose = $self->{verbose};
    if (defined $verbose) {
        if ($verbose == 1) {
            push @$params, "-v";
        } elsif ($verbose > 1) {
            push @$params, "-vv";
        }
    }

    push @$params, $self->{other_argv} if defined $self->{other_argv};

    my $params_str = join " ", @$params;

    my $start_hook;
    if (defined $self->{ulimit}) {
        $start_hook = sub {
            for my $name (keys %{$self->{ulimit}}) {
                my $value = $self->{ulimit}{$name};
                my $result = BSD::Resource::setrlimit($name, $value, $value);
                unless ($result) {
                    die "Failed to set $name=$value ulimit";
                }
            }
        };
    }
    start_daemon({
        bin => "$self->{binary} $params_str",
        pidfile => $self->{pidfile},
        ($self->{logfile} ?
            (
            stdout => $self->{logfile},
            stderr => $self->{logfile},
            ) : ()
        ),
        ($start_hook ? (start_hook => $start_hook) : ()),
        ($self->{ubic_log} ? (ubic_log => $self->{ubic_log}) : ()),
    });
    return result('starting');
}

sub stop_impl {
    my $self = shift;
    stop_daemon($self->{pidfile});
}

sub timeout_options {
    { start => { step => 0.1, trials => 10 } };
}

sub _is_available {
    my $self = shift;

    # using undocumented function here; Cache::Memcached caches unavailable hosts,
    # so without this call restart fails (at least on debian etch)
    Cache::Memcached->forget_dead_hosts();

    # TODO - this can fail if memcached binds only to specific interface
    my $client = Cache::Memcached->new({ servers => ["127.0.0.1:$self->{port}"] });
    my $key = 'Ubic::Service::Memcached-testkey';
    $client->set($key, 1);
    my $value = $client->get($key);
    $client->disconnect_all; # Cache::Memcached tries to reuse dead socket otherwise
    return $value;
}

sub status_impl {
    my $self = shift;
    if (check_daemon($self->{pidfile})) {
        if ($self->_is_available) {
            return 'running';
        }
        else {
            return 'broken';
        }
    }
    else {
        return 'not running';
    }
}

sub user {
    my $self = shift;
    return $self->{user};
}

sub group {
    my $self = shift;
    my $groups = $self->{group};
    return $self->SUPER::group() if not defined $groups;
    return @$groups if ref $groups eq 'ARRAY';
    return $groups;
}

sub port {
    my $self = shift;
    return $self->{port};
}

=back

=cut

1;
