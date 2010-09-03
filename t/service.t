#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use lib 'lib';

use Yandex::X;

use Ubic::Service::Memcached;
use Cache::Memcached;

my $port = 1358; # TODO - select any free port

# tests with verbose=2

xsystem('rm -rf tfiles');
xsystem('mkdir tfiles');

my $service = Ubic::Service::Memcached->new({
    port => $port,
    maxsize => 10,
    verbose => 2,
    logfile => 'tfiles/memcached-test.log',
    pidfile => 'tfiles/memcached-test.pid',
    ubic_log => 'tfiles/ubic.log',
    user => $ENV{LOGNAME},
});

$service->start;
is($service->status, 'running', 'start works');

my $memcached = new Cache::Memcached {
    servers => ["127.0.0.1:$port"],
};
$memcached->set('key1', 'value1');
is($memcached->get('key1'), 'value1', 'memcached responded');

$service->stop;
is($service->status, 'not running', 'stop works');

is($memcached->get('key1'), undef, 'memcached is down');

open my $fh, '<', 'tfiles/memcached-test.log' or die "Can't open log: $!";
my $log_content = do { local $/; <$fh> };
like($log_content, qr/set key1/, 'log contains memcached events');

is($service->port, $port, 'port method');

# TODO - check more thoroughly start/stop return values

