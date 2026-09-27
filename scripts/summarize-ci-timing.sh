#!/bin/bash
# Diagnostic only: malformed or absent evidence cannot change the CI verdict.
set +e
evidence_dir="${LANE_EVENT_STREAM_DIR:-tmp/plan-workflows/ci-runs}"
summary_file="$evidence_dir/timing-summary.md"
mkdir -p "$evidence_dir" 2>/dev/null || true
TIMING_EVIDENCE_DIR="$evidence_dir" /usr/bin/perl -MJSON::PP -MTime::Local -MFile::Find -e '
  use strict; use warnings;
  my $root = $ENV{TIMING_EVIDENCE_DIR};
  my $stats_dir = $ENV{SWIFT_BUILD_STATS_DIR} // "$root/compiler-stats";
  sub read_json {
    my ($file) = @_; open my $fh, "<", $file or return undef;
    local $/; my $raw = <$fh>; close $fh;
    return eval { decode_json($raw) };
  }
  sub numeric { defined $_[0] && $_[0] =~ /^-?[0-9]+(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?$/i }
  sub span {
    my ($start, $end) = @_;
    return undef unless numeric($start) && numeric($end) && $end >= $start;
    return $end - $start;
  }
  sub seconds { defined $_[0] ? sprintf("%.3f", $_[0] / 1000) : "unknown" }
  sub event_ms {
    my ($event) = @_;
    if (ref($event->{payload}) eq "HASH") { return event_ms($event->{payload}) }
    if (ref($event->{instant}) eq "HASH" && numeric($event->{instant}{since1970})) {
      return int($event->{instant}{since1970} * 1000 + 0.5);
    }
    for my $key (qw(timestamp time instant)) {
      my $value = $event->{$key};
      if (numeric($value)) { return $value >= 1000000000 && $value < 100000000000 ? $value * 1000 : $value }
      if (defined($value) && !ref($value) &&
          $value =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.(\d+))?Z$/) {
        my ($year,$month,$day,$hour,$minute,$second,$fraction) = ($1,$2,$3,$4,$5,$6,$7 // "");
        $fraction = substr($fraction . "000", 0, 3);
        return timegm($second,$minute,$hour,$day,$month-1,$year) * 1000 + $fraction;
      }
    }
    return undef;
  }
  sub run_boundaries {
    my ($file) = @_;
    return (undef, undef) unless defined($file) && -r $file;
    open my $fh, "<", $file or return (undef, undef);
    my ($started, $ended);
    while (my $line = <$fh>) {
      my $event = eval { decode_json($line) }; next unless ref($event) eq "HASH";
      my $kind = ref($event->{payload}) eq "HASH"
        ? ($event->{payload}{kind} // "") : ($event->{kind} // "");
      my $time = event_ms($event);
      $started = $time if $kind eq "runStarted" && defined($time) && !defined($started);
      $ended = $time if $kind eq "runEnded" && defined($time);
    }
    close $fh; return ($started, $ended);
  }
  my @files = sort glob("$root/lane-*.timing.json");
  my %lanes; my @records; my $unknown = 0;
  for my $file (@files) {
    my $record = read_json($file);
    unless (ref($record) eq "HASH") { $unknown++; next }
    $record->{_file} = $file;
    my ($run_start,$run_end) = run_boundaries($record->{event_stream_file});
    $record->{_wall} = span($record->{dispatch_ms}, $record->{wrapper_complete_ms});
    $record->{_startup} = span($record->{command_start_ms}, $run_start);
    $record->{_execution} = span($run_start, $run_end);
    $record->{_exit_tail} = span($run_end, $record->{command_exit_ms});
    $record->{_wrapper_tail} = span($record->{command_exit_ms}, $record->{wrapper_complete_ms});
    $unknown += scalar grep { !defined($record->{$_}) } qw(_wall _startup _execution _exit_tail _wrapper_tail);
    push @records, $record;
    push @{$lanes{$record->{lane} // "unknown"}}, $record;
  }
  print "# CI timing ledger\n\n";
  print "Diagnostic epoch timestamps; durations in seconds. Missing spans are unknown.\n\n";
  print "| Lane | Invocations | Wall | Σ startup | Σ execution | Σ exit tail | Σ wrapper tail |\n";
  print "| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n";
  for my $lane (sort keys %lanes) {
    my @items = @{$lanes{$lane}};
    my ($first,$last);
    for my $item (@items) {
      my $dispatch = $item->{dispatch_ms}; my $complete = $item->{wrapper_complete_ms};
      $first = $dispatch if numeric($dispatch) && (!defined($first) || $dispatch < $first);
      $last = $complete if numeric($complete) && (!defined($last) || $complete > $last);
    }
    my @totals;
    for my $field (qw(_startup _execution _exit_tail _wrapper_tail)) {
      my @known = grep { defined($_->{$field}) } @items;
      push @totals, @known == @items ? seconds(eval(join "+", map { $_->{$field} } @items)) : "unknown";
    }
    print "| $lane | ",scalar(@items)," | ",seconds(span($first,$last))," | ",join(" | ",@totals)," |\n";
  }
  print "| unknown | unknown | unknown | unknown | unknown | unknown | unknown |\n" unless @records;
  for my $field (["_wall","wall"],["_startup","startup"]) {
    print "\n## Top 15 invocations by $field->[1]\n\n";
    print "| Lane / label | Seconds |\n| --- | ---: |\n";
    my @ranked = sort { ($b->{$field->[0]} // -1) <=> ($a->{$field->[0]} // -1) } @records;
    for my $item (@ranked[0 .. ($#ranked < 14 ? $#ranked : 14)]) {
      print "| ",($item->{lane}//"unknown")," / ",($item->{label}//"unknown")," | ",seconds($item->{$field->[0]})," |\n";
    }
    print "| unknown | unknown |\n" unless @ranked;
  }
  print "\n## Isolated scheduler\n\n";
  print "Measured dispatch-to-wrapper spans. Idle includes startup and tail gaps across the recorded slot cap. Sidecars without a cap are omitted.\n\n";
  print "| Lane | Dispatches | Slots | Phase wall | Slot idle |\n| --- | ---: | ---: | ---: | ---: |\n";
  my %scheduler;
  for my $item (@records) {
    next unless defined($item->{filter}) && defined($item->{batch_id}) &&
      numeric($item->{slot}) && numeric($item->{slot_cap}) && $item->{slot_cap} >= 1;
    push @{$scheduler{$item->{lane}//"unknown"}}, $item;
  }
  for my $lane (sort keys %scheduler) {
    my @items = @{$scheduler{$lane}};
    my ($first,$last,$eligible,$slots,$busy) = (undef,undef,undef,undef,0);
    my $known = 1;
    for my $item (@items) {
      my $duration = span($item->{dispatch_ms},$item->{wrapper_complete_ms});
      unless (defined($duration) && $item->{slot} >= 1 && $item->{slot} <= $item->{slot_cap}) {
        $known=0; next;
      }
      $busy += $duration;
      $known=0 if defined($slots) && $slots != $item->{slot_cap};
      $slots = $item->{slot_cap};
      $first = $item->{dispatch_ms} if !defined($first) || $item->{dispatch_ms} < $first;
      $last = $item->{wrapper_complete_ms} if !defined($last) || $item->{wrapper_complete_ms} > $last;
      $eligible = $item->{eligible_ms} if numeric($item->{eligible_ms}) &&
        (!defined($eligible) || $item->{eligible_ms} < $eligible);
    }
    $first = $eligible if defined($eligible) && (!defined($first) || $eligible < $first);
    my $wall = $known ? span($first,$last) : undef;
    my $idle = defined($wall) ? $slots * $wall - $busy : undef;
    $idle = undef if defined($idle) && $idle < 0;
    print "| $lane | ",scalar(@items)," | ",($slots//"unknown")," | ",seconds($wall)," | ",seconds($idle)," |\n";
  }
  print "| unknown | unknown | unknown | unknown | unknown |\n" unless %scheduler;
  my @prebuild=grep { ($_->{label}//"") eq "prebuild test bundles" } @records;
  print "\n## Prebuild and compiler work\n\nPrebuild wall: ",
    (@prebuild ? seconds($prebuild[-1]{_wall}) : "unknown")," s.\n\n";
  print "Top 15 modules by summed frontend time (overlaps — not wall):\n\n";
  print "| Module | Summed frontend seconds |\n| --- | ---: |\n";
  my %modules;
  if (-d $stats_dir) {
    find({no_chdir => 1, wanted => sub {
      return unless -f $_ && /\.json$/;
      my $stats=read_json($File::Find::name); return unless ref($stats) eq "HASH";
      for my $key (keys %$stats) {
        next unless $key =~ /^time\.swift-frontend\.([^-]+)-.*\.wall$/;
        next unless numeric($stats->{$key});
        $modules{$1} += $stats->{$key} * 1000;
      }
    }}, $stats_dir);
  }
  my @modules=sort { $modules{$b}<=>$modules{$a} } keys %modules;
  for my $module (@modules[0 .. ($#modules<14?$#modules:14)]) {
    print "| $module | ",seconds($modules{$module})," |\n";
  }
  print "| unknown | unknown |\n" unless @modules;
  print "\nUnknown/null spans: ",(@records ? $unknown : "unknown (no sidecars)"),".\n";
' >"$summary_file" 2>/dev/null || printf '# CI timing ledger\n\nunknown (summary parser unavailable).\n' >"$summary_file"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$summary_file" >>"$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi
exit 0
