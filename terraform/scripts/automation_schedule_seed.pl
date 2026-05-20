#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use POSIX qw(tzset);
use Time::Local qw(timegm timelocal);

sub parse_rfc3339_epoch {
    my ($value) = @_;

    die "invalid RFC3339 timestamp: $value"
        unless $value =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|([+-])(\d{2}):?(\d{2}))$/;

    my ($year, $month, $day, $hour, $minute, $second) = ($1, $2, $3, $4, $5, $6);
    my $offset = 0;
    if ($7 ne 'Z') {
        $offset = ($9 * 3600) + ($10 * 60);
        $offset *= -1 if $8 eq '-';
    }

    return timegm($second, $minute, $hour, $day, $month - 1, $year) - $offset;
}

sub utc_rfc3339 {
    my ($epoch) = @_;
    my @t = gmtime($epoch);
    return sprintf(
        '%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]
    );
}

sub with_timezone {
    my ($tz, $callback) = @_;

    my $old_tz = $ENV{TZ};
    $ENV{TZ} = $tz;
    tzset();

    my $ok = eval {
        $callback->();
        1;
    };
    my $err = $@;

    if (defined $old_tz) {
        $ENV{TZ} = $old_tz;
    }
    else {
        delete $ENV{TZ};
    }
    tzset();

    die $err unless $ok;
}

sub next_weekday_occurrence {
    my ($anchor_epoch, $tz, $hhmm) = @_;

    my ($hour, $minute) = split /:/, $hhmm, 2;
    die "invalid time format: $hhmm" unless defined $hour && defined $minute;
    die "invalid time format: $hhmm" unless $hour =~ /^\d{1,2}$/ && $minute =~ /^\d{1,2}$/;
    $hour = int($hour);
    $minute = int($minute);
    die "invalid time format: $hhmm" unless $hour >= 0 && $hour <= 23 && $minute >= 0 && $minute <= 59;

    my $result;
    with_timezone($tz, sub {
        my @anchor_local = localtime($anchor_epoch);
        my ($day, $month, $year) = ($anchor_local[3], $anchor_local[4], $anchor_local[5] + 1900);

        while (1) {
            my $candidate_epoch = timelocal(0, $minute, $hour, $day, $month, $year);
            my @candidate_local = localtime($candidate_epoch);
            my $wday = $candidate_local[6] == 0 ? 7 : $candidate_local[6];

            if ($wday >= 1 && $wday <= 5 && $anchor_epoch < $candidate_epoch) {
                $result = utc_rfc3339($candidate_epoch);
                last;
            }

            my $next_noon = timelocal(0, 0, 12, $day + 1, $month, $year);
            my @next_local = localtime($next_noon);
            ($day, $month, $year) = ($next_local[3], $next_local[4], $next_local[5] + 1900);
        }
    });

    return $result;
}

my $stdin = do { local $/ = undef; <STDIN> };
my $query = decode_json($stdin // '{}');

my $anchor_rfc3339 = $query->{anchor_rfc3339} // die "missing anchor_rfc3339";
my $anchor_epoch = parse_rfc3339_epoch($anchor_rfc3339);

my $timezone      = $query->{timezone}      // die "missing timezone";
my $startup_time  = $query->{startup_time}  // die "missing startup_time";
my $shutdown_time = $query->{shutdown_time} // die "missing shutdown_time";

my %result = (
    startup_start  => next_weekday_occurrence($anchor_epoch, $timezone, $startup_time),
    shutdown_start => next_weekday_occurrence($anchor_epoch, $timezone, $shutdown_time),
);

print encode_json(\%result);
