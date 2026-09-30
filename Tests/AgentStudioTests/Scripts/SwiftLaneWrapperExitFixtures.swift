import Foundation

enum SwiftLaneWrapperExitFixtures {
    static func wrapperExitCommand(bashInterpreter: String, failureMode: String) -> String {
        "\(bashInterpreter) -c \(shellQuotedCommand(wrapperExitScript)) fixture \(shellQuotedCommand(failureMode))"
    }

    private static func shellQuotedCommand(_ command: String) -> String {
        "'" + command.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static let wrapperExitScript = #"""
        #!/usr/bin/env bash
        set -euo pipefail
        source scripts/swift-test-helpers.sh
        LOG_PREFIX=wrapper-exit-probe
        failure_mode="$1"
        printf 'BASH_INTERPRETER version=%s\n' "$BASH_VERSION"
        fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/wrapper-exit-probe.XXXXXX")"
        dispatcher_pid=""
        cleanup_fixture() {
          if [ -n "$dispatcher_pid" ]; then
            kill -CONT "$dispatcher_pid" 2>/dev/null || true
            terminate_lane_child_tree KILL "$dispatcher_pid"
            wait "$dispatcher_pid" 2>/dev/null || true
          fi
          rm -f "$fixture_dir"/*
          rmdir "$fixture_dir"
        }
        trap cleanup_fixture EXIT
        LANE_EVENT_STREAM_DIR="$fixture_dir"
        SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE="$fixture_dir/failures"

        swift_test_isolated_process_concurrency() { echo 1; }
        run_selected_isolated_suite() { printf 'COMPLETED %s\n' "$2"; }

        # The existing PID handshake is before the worker starts and before the
        # completion write. Fail exactly there; neither path relies on scheduling.
        read() {
          builtin read "$@" || return $?
          if [ "$failure_mode" = coalesced ] && [ "$*" = '-r child_pid' ]; then
            case "$suite_filter" in
              VictimOne|VictimTwo)
                exec 9>"$fixture_dir/exited-$slot"
                printf 'READY %s %s\n' "$slot" "$child_pid" >&8
                builtin read -r release <"$fixture_dir/release-$slot"
                ;;
            esac
          fi
          if [ "$*" = '-r child_pid' ] && [ "$suite_filter" = Victim ]; then
            case "$failure_mode" in
              kill) kill -KILL "$child_pid" ;;
              errexit) return 73 ;;
              *) return 74 ;;
            esac
          fi
          return 0
        }

        # An unguarded asynchronous call preserves errexit in the wrapper.
        # Guarding dispatch with || would disable errexit inside its subshells as well.
        if [ "$failure_mode" = coalesced ]; then
          swift_test_isolated_process_concurrency() { echo 2; }
          mkfifo "$fixture_dir/events"
          for slot in 1 2; do
            mkfifo "$fixture_dir/exited-$slot" "$fixture_dir/release-$slot"
          done
          exec 8<>"$fixture_dir/events"
          dispatch_isolated_suites fast VictimOne VictimTwo AfterOne AfterTwo & dispatcher_pid=$!
          exec 9<"$fixture_dir/exited-1"
          exec 10<"$fixture_dir/exited-2"
          read -r -u 8 first_event first_slot first_pid
          read -r -u 8 second_event second_slot second_pid
          [ "$first_event|$second_event" = 'READY|READY' ] || exit 45
          # Hold only the dispatcher. EOF proves both wrappers have closed their last
          # lifetime writer before it resumes and consumes their terminal records.
          kill -STOP "$dispatcher_pid"
          kill -KILL "$first_pid" "$second_pid"
          if read -r -u 9 unexpected; then exit 46; fi
          if read -r -u 10 unexpected; then exit 47; fi
          kill -CONT "$dispatcher_pid"
        else
          dispatch_isolated_suites fast Victim After & dispatcher_pid=$!
        fi
        dispatcher_status=0
        wait "$dispatcher_pid" || dispatcher_status=$?
        dispatcher_pid=""
        [ "$dispatcher_status" -eq 1 ] || exit 41
        case "$failure_mode" in
          kill|errexit)
            [ "$(swift_test_failed_isolated_suite_count)" -eq 1 ] || exit 42
            expected_status=$'Victim\t73\tnone'
            [ "$failure_mode" != kill ] || expected_status=$'Victim\t137\tKILL'
            grep -q "$expected_status" "$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE"
            ;;
          coalesced)
            [ "$(swift_test_failed_isolated_suite_count)" -eq 2 ] || exit 42
            grep -q $'VictimOne\t137\tKILL' "$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE"
            grep -q $'VictimTwo\t137\tKILL' "$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE"
            ;;
        esac
        [ -z "$(jobs -pr)" ] || exit 43
        [ "$(find "$fixture_dir" -name 'agentstudio-isolated-dispatch.*' -print)" = '' ] || exit 44
        printf 'WRAPPER_EXIT_DRAINED mode=%s\n' "$failure_mode"
        """#
}
