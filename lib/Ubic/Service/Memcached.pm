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

=head1 METHODS

=over

=cut

use parent qw(Ubic::Service::Skeleton);
use Ubic::Daemon qw(:all);
use Ubic::Result qw(result);
use Cache::Memcached;
use Time::HiRes qw(sleep time);

use Params::Validate qw(:all);

=item B<< new($params) >>

Constructor.

Parameters:

=over

=item I<port>

Integer port number.

=item I<pidfile>

Full path to pidfile. Pidfile will be managed by C<Ubic::Daemon>.

=item I<maxsize>

Max memcached memory size in megabytes. Default is 640MB.

=item I<verbose>

Enable memcached logging.

C<verbose=1>> turns on basic error and warning logs (i.e. it sets C<-v> switch),

C<verbose=2> turns on more detailed logging (i.e. it sets C<-vv> switch).


=item I<logfile>

If specified, memcached will be configured to write logs to given file.

=item I<ubic_log>

Optional log with ubic-specific messages.

=item I<user>

=item I<group>

As usual, you can specify custom user and group values. Default is C<root:root>.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        port => { type => SCALAR, regex => qr/^\d+$/ },
        pidfile => { type => SCALAR },
        maxsize => { type => SCALAR, regex => qr/^\d+$/, default => 640 },
        verbose => { type => SCALAR, optional => 1 },
        logfile => { type => SCALAR, optional => 1 },
        ubic_log => { type => SCALAR, optional => 1 },
        user => { type => SCALAR, default => 'root' },
        group => { type => SCALAR, optional => 1},
    });
    return bless $params => $class;
}

sub start_impl {
    my $self = shift;

    my $params;

    push @$params, "-u $self->{user}" if $self->{user} eq 'root';
    push @$params, "-p $self->{port}";
    push @$params, "-m $self->{maxsize}";
    my $verbose = $self->{verbose};
    if (defined($verbose) && $verbose == 1) {
        push @$params, "-v";
    } elsif ($verbose > 1) {
        push @$params, "-vv";
    }

    $params = join " ", @$params;

    start_daemon({
        bin => "/usr/bin/memcached $params",
        pidfile => $self->{pidfile},
        ($self->{logfile} ?
            (
            stdout => $self->{logfile},
            stderr => $self->{logfile},
            ) : ()
        ),
        ($self->{ubic_log} ? (ubic_log => $self->{ubic_log}) : ()),
    });
    my $check_started = time;
    for my $trial (1..10) {
        if ($self->_is_available) {
            return result('started');
        }
        sleep($trial / 10);
    }
    die "can't get answer in ".(time - $check_started)." seconds";
}

sub stop_impl {
    my $self = shift;
    stop_daemon($self->{pidfile});
}

sub _is_available {
    my $self = shift;

    # using undocumented function here; Cache::Memcached caches unavailable hosts,
    # so without this call restart fails at least on etch
    Cache::Memcached->forget_dead_hosts();

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

