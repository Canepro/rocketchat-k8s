#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);

sub run_cmd {
    my (@cmd) = @_;
    open my $fh, '-|', @cmd or die "failed to run command (@cmd): $!";
    local $/ = undef;
    my $out = <$fh>;
    close $fh;
    die "command failed (@cmd)" if $?;
    $out = '' unless defined $out;
    $out =~ s/\r?\n\z//;
    return $out;
}

sub next_weekday_occurrence {
    my ($anchor_epoch, $tz, $hhmm) = @_;

    my ($hour, $minute) = split /:/, $hhmm, 2;
    die "invalid time format: $hhmm" unless defined $hour && defined $minute;
    die "invalid time format: $hhmm" unless $hour =~ /^\d{1,2}$/ && $minute =~ /^\d{1,2}$/;
    $hour = int($hour);
    $minute = int($minute);
    die "invalid time format: $hhmm" unless $hour >= 0 && $hour <= 23 && $minute >= 0 && $minute <= 59;

    my $candidate_date = run_cmd('env', "TZ=$tz", 'date', '-d', "\@$anchor_epoch", '+%Y-%m-%d');
    while (1) {
        my $weekday = run_cmd('env', "TZ=$tz", 'date', '-d', $candidate_date, '+%u');
        my $candidate_epoch = run_cmd('env', "TZ=$tz", 'date', '-d', "$candidate_date $hour:$minute", '+%s');

        if ($weekday >= 1 && $weekday <= 5 && $anchor_epoch < $candidate_epoch) {
            return run_cmd('date', '-u', '-d', "\@$candidate_epoch", '+%Y-%m-%dT%H:%M:%SZ');
        }

        $candidate_date = run_cmd('env', "TZ=$tz", 'date', '-d', "$candidate_date + 1 day", '+%Y-%m-%d');
    }
}

my $stdin = do { local $/ = undef; <STDIN> };
my $query = decode_json($stdin // '{}');

my $anchor_rfc3339 = $query->{anchor_rfc3339} // die "missing anchor_rfc3339";
$anchor_rfc3339 =~ s/Z$/+00:00/;
my $anchor_epoch = run_cmd('date', '-u', '-d', $anchor_rfc3339, '+%s');

my $timezone      = $query->{timezone}      // die "missing timezone";
my $startup_time  = $query->{startup_time}  // die "missing startup_time";
my $shutdown_time = $query->{shutdown_time} // die "missing shutdown_time";

my %result = (
    startup_start  => next_weekday_occurrence($anchor_epoch, $timezone, $startup_time),
    shutdown_start => next_weekday_occurrence($anchor_epoch, $timezone, $shutdown_time),
);

print encode_json(\%result);
