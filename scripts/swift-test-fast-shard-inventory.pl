#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
use Scalar::Util qw(looks_like_number);

my $json = JSON::PP->new->utf8->canonical;
my $mode = shift @ARGV // '';

sub fail {
    die $_[0] . "\n";
}

sub read_json_file {
    my ($path, $label) = @_;
    open my $input, '<:raw', $path or fail("$label: cannot open $path: $!");
    local $/;
    my $record = eval { $json->decode(<$input>) };
    close $input;
    fail("$label: invalid JSON in $path") unless ref($record) eq 'HASH';
    return $record;
}

sub write_json_file {
    my ($path, $record) = @_;
    open my $output, '>:raw', "$path.tmp-$$" or fail("cannot write $path: $!");
    print {$output} $json->encode($record), "\n" or fail("cannot write $path: $!");
    close $output or fail("cannot close $path: $!");
    rename "$path.tmp-$$", $path or fail("cannot replace $path: $!");
}

sub read_events {
    my ($path, $label) = @_;
    open my $input, '<:raw', $path or fail("$label: cannot open $path: $!");
    my @records;
    my $line_number = 0;
    while (my $line = <$input>) {
        $line_number++;
        fail("$label: unterminated_event_line=$line_number") unless $line =~ /\n\z/;
        my $record = eval { $json->decode($line) };
        fail("$label: invalid_event_json line=$line_number") unless ref($record) eq 'HASH';
        push @records, $record;
    }
    close $input or fail("$label: cannot close $path: $!");
    return \@records;
}

sub normalized_function_id {
    my ($definition) = @_;
    my $id = $definition->{id} // '';
    $id =~ s{/[^/]+:\d+:\d+\z}{};
    return $id;
}

sub suite_for_function {
    my ($function_id, $suite_ids) = @_;
    for my $suite_id (sort { length($b) <=> length($a) || $a cmp $b } @$suite_ids) {
        return $suite_id if index($function_id, "$suite_id/") == 0;
    }
    return undef;
}

sub event_payload {
    my ($record) = @_;
    return ref($record->{payload}) eq 'HASH' ? $record->{payload} : $record;
}

sub stable_case_ids {
    my ($function_definition) = @_;
    my $cases = $function_definition->{_testCases};
    return () unless ref($cases) eq 'ARRAY';
    return map { $_->{id} }
        grep { ref($_) eq 'HASH' && $_->{isStable} && defined($_->{id}) }
        @$cases;
}

sub unstable_case_count {
    my ($function_definition) = @_;
    my $cases = $function_definition->{_testCases};
    return 0 unless ref($cases) eq 'ARRAY';
    return scalar grep { ref($_) eq 'HASH' && !$_->{isStable} } @$cases;
}

sub case_display_names {
    my ($function_definition) = @_;
    my $cases = $function_definition->{_testCases};
    return () unless ref($cases) eq 'ARRAY';
    return map { defined($_->{displayName}) ? $_->{displayName} : '' }
        grep { ref($_) eq 'HASH' } @$cases;
}

sub parse_event_ledger {
    my ($path, $label) = @_;
    my $records = read_events($path, $label);
    my $error_prefix = $label eq 'manifest_error' ? 'manifest_error=' : "$label: ";
    my (%suite_definitions, %function_definitions, %event_starts, %event_ends,
        %case_starts, %case_ends, %case_start_records, %case_end_records);
    my ($run_started, $run_ended, $issue_count, $unclassified_count) = (0, 0, 0, 0);

    for my $record (@$records) {
        my $payload = event_payload($record);
        if (($record->{kind} // '') eq 'test') {
            my $kind = $payload->{kind} // '';
            my $id = $payload->{id} // '';
            if ($kind eq 'suite' && length $id) {
                $suite_definitions{$id} = $payload;
            } elsif ($kind eq 'function' && length $id) {
                my $function_id = normalized_function_id($payload);
                fail("${error_prefix}duplicate_function_definition function=$function_id")
                    if exists $function_definitions{$function_id};
                $function_definitions{$function_id} = $payload;
            }
            next;
        }

        next unless ($record->{kind} // '') eq 'event';
        my $kind = $payload->{kind} // '';
        $run_started++ if $kind eq 'runStarted';
        $run_ended++ if $kind eq 'runEnded';
        $issue_count++ if $kind eq 'issueRecorded';
        my $raw_id = $payload->{testID} // '';
        if ($kind eq 'testStarted' || $kind eq 'testEnded') {
            next if exists $suite_definitions{$raw_id};
            my $function_id = $raw_id;
            $function_id =~ s{/[^/]+:\d+:\d+\z}{};
            if (!exists $function_definitions{$function_id}) {
                $unclassified_count++;
                next;
            }
            if ($kind eq 'testStarted') { $event_starts{$function_id}++ }
            else { $event_ends{$function_id}++ }
        } elsif ($kind eq 'testCaseStarted' || $kind eq 'testCaseEnded') {
            my $case = $payload->{_testCase};
            my $case_id = ref($case) eq 'HASH' ? ($case->{id} // '') : '';
            fail("${error_prefix}parameter_case_without_identity") unless length($raw_id) && length($case_id);
            my $function_id = $raw_id;
            $function_id =~ s{/[^/]+:\d+:\d+\z}{};
            my $key = "$function_id\0$case_id";
            if ($kind eq 'testCaseStarted') {
                $case_starts{$key}++;
                $case_start_records{$key} = {
                    function_id => $function_id, id => $case_id,
                    display_name => $case->{displayName} // '',
                };
            } else {
                $case_ends{$key}++;
                $case_end_records{$key} = {
                    function_id => $function_id, id => $case_id,
                    display_name => $case->{displayName} // '',
                };
            }
        }
    }

    my @suite_ids = sort keys %suite_definitions;
    my @functions;
    for my $function_id (sort keys %function_definitions) {
        my $definition = $function_definitions{$function_id};
        my $suite_id = suite_for_function($function_id, \@suite_ids);
        fail("${error_prefix}function_without_suite function=$function_id") unless defined $suite_id;
        my $starts = $event_starts{$function_id} // 0;
        my $ends = $event_ends{$function_id} // 0;
        fail("${error_prefix}unstarted_function function=$function_id") unless $starts == 1;
        fail("${error_prefix}unended_function function=$function_id") unless $ends == 1;

        my @defined_cases = ref($definition->{_testCases}) eq 'ARRAY'
            ? @{$definition->{_testCases}} : ();
        my %defined_case_ids = map { ($_->{id} // '') => $_ }
            grep { ref($_) eq 'HASH' && defined($_->{id}) } @defined_cases;
        my @observed_case_keys = grep { index($_, "$function_id\0") == 0 } keys %case_starts;
        for my $key (@observed_case_keys) {
            my ($case_function_id, $case_id) = split /\0/, $key, 2;
            fail("${error_prefix}unclassified_case function=$case_function_id")
                if @defined_cases && !exists $defined_case_ids{$case_id};
            fail("${error_prefix}unended_case function=$function_id case=$case_id")
                unless ($case_ends{$key} // 0) == 1;
            fail("${error_prefix}duplicate_case_start function=$function_id case=$case_id")
                unless $case_starts{$key} == 1;
        }
        for my $case_id (sort keys %defined_case_ids) {
            my $key = "$function_id\0$case_id";
            fail("${error_prefix}unstarted_case function=$function_id case=$case_id")
                unless ($case_starts{$key} // 0) == 1;
            fail("${error_prefix}unended_case function=$function_id case=$case_id")
                unless ($case_ends{$key} // 0) == 1;
        }

        my @display_names = case_display_names($definition);
        my @stable_ids = sort stable_case_ids($definition);
        my $unstable_count = unstable_case_count($definition);
        push @functions, {
            id => $function_id,
            suite_id => $suite_id,
            name => $definition->{name} // '',
            parameterized => $definition->{isParameterized} ? JSON::PP::true : JSON::PP::false,
            case_count => scalar(@defined_cases),
            case_display_names => [sort @display_names],
            stable_case_ids => \@stable_ids,
            unstable_case_count => $unstable_count,
        };
    }

    fail("${error_prefix}run_started_count=$run_started") unless $run_started == 1;
    fail("${error_prefix}run_ended_count=$run_ended") unless $run_ended == 1;
    fail("${error_prefix}unclassified_test_events=$unclassified_count") if $unclassified_count;
    return {
        suites => [map {
            my $type_path = $_;
            $type_path =~ s/^[^.]+\.//;
            { id => $_, type_path => $type_path }
        } @suite_ids],
        functions => \@functions,
        function_definitions => \%function_definitions,
        suite_definitions => \%suite_definitions,
        event_started => \%event_starts,
        event_ended => \%event_ends,
        case_starts => \%case_starts,
        case_ends => \%case_ends,
        case_start_records => \%case_start_records,
        case_end_records => \%case_end_records,
    };
}

sub validate_timing_receipt {
    my ($path, $label, $expected_functions, $expected_cases, $require_first_output) = @_;
    my $timing = read_json_file($path, "$label timing");
    fail("$label: command_status_not_zero") unless defined($timing->{command_status}) && $timing->{command_status} == 0;
    for my $field (qw(announced_tests ended_tests started_parameterized_cases ended_parameterized_cases)) {
        fail("$label: missing_timing_count field=$field") unless defined $timing->{$field};
    }
    fail("$label: timing_function_count_mismatch")
        unless $timing->{announced_tests} == $expected_functions
            && $timing->{ended_tests} == $expected_functions;
    fail("$label: timing_case_count_mismatch")
        unless $timing->{started_parameterized_cases} == $expected_cases
            && $timing->{ended_parameterized_cases} == $expected_cases;
    if ($require_first_output) {
        my $first_output = $timing->{start_to_first_output_seconds};
        fail("$label: missing_start_to_first_output")
            unless defined($first_output) && !ref($first_output) && looks_like_number($first_output) && $first_output >= 0;
    }
    return $timing;
}

sub manifest_weight_by_suite {
    my ($manifest) = @_;
    my %weights = map { $_->{id} => 0 } @{$manifest->{suites}};
    my %functions;
    for my $function (@{$manifest->{functions}}) {
        my $suite_id = $function->{suite_id};
        fail("manifest_error=function_without_suite function=$function->{id}")
            unless exists $weights{$suite_id};
        fail("manifest_error=duplicate_function function=$function->{id}")
            if $functions{$function->{id}}++;
        my $case_count = defined($function->{case_count}) ? $function->{case_count}
            : scalar(@{$function->{case_display_names} // []});
        fail("manifest_error=invalid_case_count function=$function->{id}")
            unless $case_count =~ /^\d+$/;
        $weights{$suite_id} += 1 + $case_count;
    }
    for my $suite_id (keys %weights) {
        fail("manifest_error=empty_suite suite=$suite_id") unless $weights{$suite_id} > 0;
    }
    return \%weights;
}

sub load_manifest {
    my ($path) = @_;
    my $manifest = read_json_file($path, 'manifest_error');
    fail('manifest_error=unsupported_schema') unless ($manifest->{schema_version} // 0) == 1;
    fail('manifest_error=missing_suites') unless ref($manifest->{suites}) eq 'ARRAY' && @{$manifest->{suites}};
    fail('manifest_error=missing_functions') unless ref($manifest->{functions}) eq 'ARRAY' && @{$manifest->{functions}};
    my %seen_suites;
    for my $suite (@{$manifest->{suites}}) {
        fail('manifest_error=invalid_suite_record') unless ref($suite) eq 'HASH' && defined($suite->{id}) && length($suite->{id});
        fail("manifest_error=duplicate_suite suite=$suite->{id}") if $seen_suites{$suite->{id}}++;
    }
    manifest_weight_by_suite($manifest);
    return $manifest;
}

sub verify_suite_inventory {
    my ($manifest_path, $inventory_path) = @_;
    my $manifest = load_manifest($manifest_path);
    open my $input, '<:raw', $inventory_path or fail("inventory_error=cannot_open_suite_list path=$inventory_path");
    my (%expected, %actual);
    for my $suite (@{$manifest->{suites}}) {
        $expected{$suite->{type_path} // $suite->{id}}++;
    }
    while (my $line = <$input>) {
        fail('inventory_error=unterminated_suite_line') unless $line =~ /\n\z/;
        chomp $line;
        next unless length $line;
        $actual{$line}++;
    }
    close $input or fail("inventory_error=cannot_close_suite_list path=$inventory_path");
    for my $suite_type (sort keys %actual) {
        fail("inventory_error=unmanifested_suite suite=$suite_type") unless $expected{$suite_type};
    }
    printf "inventory_pass suites=%d\n", scalar(@{$manifest->{suites}});
}

sub shard_plan {
    my ($manifest, $capacity) = @_;
    fail('plan_error=invalid_capacity') unless defined($capacity) && $capacity =~ /^[1-9]\d*$/;
    my $weights = manifest_weight_by_suite($manifest);
    my @work = sort { $weights->{$b} <=> $weights->{$a} || $a cmp $b } keys %$weights;
    my @shards;
    for my $suite_id (@work) {
        my $weight = $weights->{$suite_id};
        fail("plan_error=suite_exceeds_capacity suite=$suite_id weight=$weight capacity=$capacity")
            if $weight > $capacity;
        my $selected;
        for my $index (0 .. $#shards) {
            next if $shards[$index]{weight} + $weight > $capacity;
            if (!defined($selected) || $shards[$index]{weight} < $shards[$selected]{weight}) {
                $selected = $index;
            }
        }
        if (!defined $selected) {
            push @shards, { weight => 0, suites => [] };
            $selected = $#shards;
        }
        $shards[$selected]{weight} += $weight;
        push @{$shards[$selected]{suites}}, $suite_id;
    }
    my @lines;
    for my $index (0 .. $#shards) {
        my $number = $index + 1;
        push @lines, join("\t", 'SHARD', $number, $shards[$index]{weight});
        push @lines, map { join("\t", 'SUITE', $number, $_) }
            sort @{$shards[$index]{suites}};
    }
    return (\@shards, \@lines);
}

sub parse_plan_file {
    my ($path, $weights) = @_;
    open my $input, '<:raw', $path or fail("coverage_error=cannot_open_plan path=$path");
    my (@shards, %suite_shard, %declared_weight);
    my $line_number = 0;
    while (my $line = <$input>) {
        $line_number++;
        fail("coverage_error=unterminated_plan_line line=$line_number") unless $line =~ /\n\z/;
        chomp $line;
        my @fields = split /\t/, $line, -1;
        if (@fields == 3 && $fields[0] eq 'SHARD') {
            my ($number, $weight) = @fields[1, 2];
            fail("coverage_error=invalid_shard number=$number") unless $number =~ /^[1-9]\d*$/ && $weight =~ /^\d+$/;
            fail("coverage_error=duplicate_shard shard=$number") if exists $declared_weight{$number};
            $declared_weight{$number} = 0 + $weight;
            $shards[$number] //= [];
        } elsif (@fields == 3 && $fields[0] eq 'SUITE') {
            my ($number, $suite_id) = @fields[1, 2];
            fail("coverage_error=unknown_suite suite=$suite_id") unless exists $weights->{$suite_id};
            fail("coverage_error=suite_before_shard shard=$number suite=$suite_id") unless exists $declared_weight{$number};
            fail("coverage_error=duplicate_suite suite=$suite_id") if exists $suite_shard{$suite_id};
            $suite_shard{$suite_id} = 0 + $number;
            push @{$shards[$number]}, $suite_id;
        } else {
            fail("coverage_error=invalid_plan_line line=$line_number");
        }
    }
    close $input or fail("coverage_error=cannot_close_plan path=$path");
    for my $suite_id (sort keys %$weights) {
        fail("coverage_error=missing_suite suite=$suite_id") unless exists $suite_shard{$suite_id};
    }
    for my $number (1 .. $#shards) {
        fail("coverage_error=missing_shard shard=$number") unless exists $declared_weight{$number};
        my $observed_weight = 0;
        $observed_weight += $weights->{$_} for @{$shards[$number] // []};
        fail("coverage_error=shard_weight_mismatch shard=$number")
            unless $observed_weight == $declared_weight{$number};
    }
    return (\@shards, \%suite_shard);
}

sub observed_function_records {
    my ($ledger, $suite_shard, $shard_number, $label) = @_;
    my %observed;
    for my $function (@{$ledger->{functions}}) {
        my $id = $function->{id};
        fail("coverage_error=unexpected_function function=$id") unless exists $suite_shard->{$function->{suite_id}};
        fail("coverage_error=function_in_wrong_shard function=$id expected_shard=$suite_shard->{$function->{suite_id}} actual_shard=$shard_number")
            unless $suite_shard->{$function->{suite_id}} == $shard_number;
        fail("coverage_error=duplicate_function function=$id") if $observed{$id};
        $observed{$id} = $function;
    }
    return \%observed;
}

sub validate_observed_cases {
    my ($expected, $observed, $ledger, $receipt_cases) = @_;
    my $function_id = $expected->{id};
    my $expected_count = defined($expected->{case_count}) ? $expected->{case_count}
        : scalar(@{$expected->{case_display_names} // []});
    my $observed_definition = $ledger->{function_definitions}{$function_id} // {};
    my @observed_defined_cases = ref($observed_definition->{_testCases}) eq 'ARRAY'
        ? @{$observed_definition->{_testCases}} : ();
    my %actual_defined_ids = map { ($_->{id} // '') => $_ }
        grep { ref($_) eq 'HASH' && defined($_->{id}) } @observed_defined_cases;
    my @actual_started_cases = sort {
        $a->{id} cmp $b->{id}
    } grep { $_->{function_id} eq $function_id } values %{$ledger->{case_start_records}};
    my @actual_ended_cases = sort {
        $a->{id} cmp $b->{id}
    } grep { $_->{function_id} eq $function_id } values %{$ledger->{case_end_records}};
    my %expected_names = map { $_ => 1 } @{$expected->{case_display_names} // []};
    my %actual_names = map { $_->{display_name} => 1 } @actual_started_cases;

    my $has_identity_metadata = exists($expected->{stable_case_ids}) || exists($expected->{unstable_case_count});
    if (!$has_identity_metadata) {
        fail("coverage_error=missing_case_display_name function=$function_id")
            if keys(%expected_names) && grep { !$actual_names{$_} } keys %expected_names;
        fail("coverage_error=unexpected_case_display_name function=$function_id")
            if keys(%expected_names) && grep { !$expected_names{$_} } keys %actual_names;
    }
    fail("coverage_error=missing_case function=$function_id")
        unless @actual_started_cases == $expected_count && @actual_ended_cases == $expected_count;

    if (exists $expected->{stable_case_ids} || exists $expected->{unstable_case_count}) {
        my %expected_stable = map { $_ => 1 } @{$expected->{stable_case_ids} // []};
        my %actual_stable = map { $_->{id} => 1 }
            grep { $_->{isStable} } @observed_defined_cases;
        fail("coverage_error=missing_stable_case function=$function_id")
            if grep { !$actual_stable{$_} } keys %expected_stable;
        fail("coverage_error=unexpected_stable_case function=$function_id")
            if grep { !$expected_stable{$_} } keys %actual_stable;
        my $expected_unstable = $expected->{unstable_case_count} // 0;
        my $actual_unstable = scalar grep { !$_->{isStable} } @observed_defined_cases;
        fail("coverage_error=unstable_case_count_mismatch function=$function_id expected=$expected_unstable actual=$actual_unstable")
            unless $expected_unstable == $actual_unstable;
    }

    my @stable_started = sort map { $_->{id} }
        grep { $actual_defined_ids{$_->{id}} && $actual_defined_ids{$_->{id}}{isStable} }
        @actual_started_cases;
    my @unstable_started = sort map { $_->{id} }
        grep { $actual_defined_ids{$_->{id}} && !$actual_defined_ids{$_->{id}}{isStable} }
        @actual_started_cases;
}

sub create_manifest {
    my ($events_path, $timing_path, $run_id, $head_sha) = @_;
    fail('manifest_error=missing_source_run_id') unless defined($run_id) && length($run_id);
    fail('manifest_error=missing_source_head_sha') unless defined($head_sha) && length($head_sha);
    my $ledger = parse_event_ledger($events_path, 'manifest_error');
    my $expected_cases = 0;
    $expected_cases += $_->{case_count} for @{$ledger->{functions}};
    validate_timing_receipt($timing_path, 'manifest_error', scalar(@{$ledger->{functions}}), $expected_cases, 0);
    my $manifest = {
        schema_version => 1,
        source_run_id => $run_id,
        source_head_sha => $head_sha,
        suites => $ledger->{suites},
        functions => $ledger->{functions},
    };
    manifest_weight_by_suite($manifest);
    return $manifest;
}

sub validate_shard_run {
    my ($manifest_path, $plan_path, $capture_directory, $receipt_path) = @_;
    my $manifest = load_manifest($manifest_path);
    my $weights = manifest_weight_by_suite($manifest);
    my ($shards, $suite_shard) = parse_plan_file($plan_path, $weights);
    my %expected_functions = map { $_->{id} => $_ } @{$manifest->{functions}};
    my %observed_functions;
    my @receipt_cases;
    my @receipt_functions;
    my @timings;
    my $observed_function_count = 0;
    my $observed_case_count = 0;
    for my $shard_number (1 .. $#$shards) {
        my $stem = sprintf('shard-%03d', $shard_number);
        my $events_path = "$capture_directory/$stem.events.jsonl";
        my $timing_path = "$capture_directory/$stem.timing.json";
        my $ledger = parse_event_ledger($events_path, "shard=$shard_number");
        my $shard_functions = observed_function_records($ledger, $suite_shard, $shard_number, "shard=$shard_number");
        my $shard_expected_count = scalar grep { $suite_shard->{$_->{suite_id}} == $shard_number }
            @{$manifest->{functions}};
        my $shard_expected_cases = 0;
        $shard_expected_cases += (defined($_->{case_count}) ? $_->{case_count} : scalar(@{$_->{case_display_names} // []}))
            for grep { $suite_shard->{$_->{suite_id}} == $shard_number } @{$manifest->{functions}};
        for my $function_id (sort keys %expected_functions) {
            my $expected = $expected_functions{$function_id};
            next unless $suite_shard->{$expected->{suite_id}} == $shard_number;
            fail("coverage_error=missing_function function=$function_id") unless exists $shard_functions->{$function_id};
        }
        for my $case_record (values %{$ledger->{case_start_records}}) {
            my $definition = $ledger->{function_definitions}{$case_record->{function_id}} // {};
            my %definitions = map { ($_->{id} // '') => $_ }
                grep { ref($_) eq 'HASH' } @{$definition->{_testCases} // []};
            my $case_definition = $definitions{$case_record->{id}} // {};
            push @receipt_cases, {
                function_id => $case_record->{function_id},
                id => $case_record->{id},
                display_name => $case_record->{display_name},
                identity_stability => $case_definition->{isStable} ? 'stable_id' : 'run_local_id',
            };
        }
        write_json_file($receipt_path, {
            schema_version => 1,
            result => 'in_progress',
            source_run_id => $manifest->{source_run_id} // '',
            source_head_sha => $manifest->{source_head_sha} // '',
            parameterized_cases => [@receipt_cases],
            shard_timings => [
                {
                    shard => $shard_number,
                    start_to_first_output_seconds =>
                        read_json_file($timing_path, "shard=$shard_number timing")->{start_to_first_output_seconds},
                },
            ],
        });
        for my $function_id (sort keys %$shard_functions) {
            my $actual = $shard_functions->{$function_id};
            my $expected = $expected_functions{$function_id};
            fail("coverage_error=unexpected_function function=$function_id") unless defined $expected;
            fail("coverage_error=function_in_wrong_suite function=$function_id")
                unless $expected->{suite_id} eq $actual->{suite_id};
            fail("coverage_error=duplicate_function function=$function_id") if $observed_functions{$function_id};
            fail("coverage_error=function_parameterization_changed function=$function_id")
                unless !!$expected->{parameterized} == !!$actual->{parameterized};
            validate_observed_cases($expected, $actual, $ledger, \@receipt_cases)
                if $expected->{parameterized} || ($expected->{case_count} // 0) > 0;
            $observed_functions{$function_id} = 1;
            push @receipt_functions, {
                id => $function_id,
                suite_id => $actual->{suite_id},
                shard => $shard_number,
            };
            $observed_function_count++;
            $observed_case_count += $actual->{case_count};
        }
        my $timing = validate_timing_receipt(
            $timing_path, "shard=$shard_number", $shard_expected_count, $shard_expected_cases, 1
        );
        push @timings, {
            shard => $shard_number,
            start_to_first_output_seconds => 0 + $timing->{start_to_first_output_seconds},
            announced_tests => 0 + $timing->{announced_tests},
            ended_tests => 0 + $timing->{ended_tests},
            started_parameterized_cases => 0 + $timing->{started_parameterized_cases},
            ended_parameterized_cases => 0 + $timing->{ended_parameterized_cases},
        };
    }

    my $receipt = {
        schema_version => 1,
        source_run_id => $manifest->{source_run_id} // '',
        source_head_sha => $manifest->{source_head_sha} // '',
        result => 'pass',
        shard_count => $#$shards,
        suite_count => scalar(@{$manifest->{suites}}),
        function_count => $observed_function_count,
        parameterized_case_count => $observed_case_count,
        suites => [map {
            { id => $_, shard => $suite_shard->{$_}, weight => $weights->{$_} }
        } sort keys %$weights],
        functions => [sort { $a->{id} cmp $b->{id} } @receipt_functions],
        parameterized_cases => [sort { $a->{function_id} cmp $b->{function_id} || $a->{id} cmp $b->{id} } @receipt_cases],
        shard_timings => \@timings,
    };
    write_json_file($receipt_path, $receipt);

    for my $function_id (sort keys %expected_functions) {
        fail("coverage_error=missing_function function=$function_id") unless exists $observed_functions{$function_id};
    }
    return $receipt;
}

my $status = eval {
    if ($mode eq 'manifest') {
        my ($events, $timing, $run_id, $head_sha) = @ARGV;
        my $manifest = create_manifest($events, $timing, $run_id, $head_sha);
        print $json->encode($manifest), "\n";
    } elsif ($mode eq 'plan') {
        my ($manifest_path, $capacity) = @ARGV;
        my $manifest = load_manifest($manifest_path);
        my (undef, $lines) = shard_plan($manifest, $capacity);
        print join("\n", @$lines), "\n";
    } elsif ($mode eq 'inventory') {
        my ($manifest_path, $inventory_path) = @ARGV;
        verify_suite_inventory($manifest_path, $inventory_path);
    } elsif ($mode eq 'validate') {
        my ($manifest_path, $plan_path, $capture_directory, $receipt_path) = @ARGV;
        my $receipt = validate_shard_run($manifest_path, $plan_path, $capture_directory, $receipt_path);
        printf "coverage_pass suites=%d functions=%d cases=%d shards=%d\n",
            $receipt->{suite_count}, $receipt->{function_count},
            $receipt->{parameterized_case_count}, $receipt->{shard_count};
    } else {
        fail('usage: swift-test-fast-shard-inventory.pl manifest|plan|inventory|validate ...');
    }
    1;
};
if (!$status) {
    my $error = $@ || "unknown shard inventory failure\n";
    $error =~ s/\s+\z//;
    if ($mode eq 'validate' && defined $ARGV[3]) {
        my $receipt_path = $ARGV[3];
        my $partial = -r $receipt_path ? eval { read_json_file($receipt_path, 'coverage_error') } : {};
        $partial = {} unless ref($partial) eq 'HASH';
        $partial->{schema_version} //= 1;
        $partial->{result} = 'fail';
        $partial->{validation_error} = $error;
        eval { write_json_file($receipt_path, $partial) };
    }
    print STDERR "$error\n";
    exit 1;
}
