import Testing

@Suite("Swift lane inventory generation")
struct SwiftLaneInventoryGenerationTests {
    @Test("lane suite list stays complete under Bash 3.2 SIGCHLD load")
    func laneSuiteListStaysCompleteUnderBash32SIGCHLDLoad() async throws {
        let result = try await runLaneScriptBash(
            """
            source scripts/swift-test-helpers.sh
            case "$BASH_VERSION" in
              3.2.*) ;;
              *) printf 'expected Bash 3.2, got %s\\n' "$BASH_VERSION" >&2; exit 2 ;;
            esac

            inventory="$(swift_test_suite_lane_inventory)" || exit 2
            expected_count=0
            while IFS='|' read -r lane suite_type mode; do
              if [ "$lane" = large ] && [ "$mode" = concurrent ]; then
                expected_count=$((expected_count + 1))
              fi
            done <<<"$inventory"

            (
              for ((noise_iteration = 0; noise_iteration < 10000; noise_iteration++)); do
                ( : )
              done
            ) &
            noise_pid=$!

            completed_iterations=0
            for ((generator_iteration = 0; generator_iteration < 1000; generator_iteration++)); do
              suite_types="$(swift_test_lane_suite_types large concurrent)"
              generator_status=$?
              if [ "$generator_status" -ne 0 ]; then
                printf 'generator_failed iteration=%s status=%s expected=%s\\n' \\
                  "$generator_iteration" "$generator_status" "$expected_count" >&2
                wait "$noise_pid"
                exit 1
              fi

              observed_count=0
              while IFS= read -r suite_type; do
                [ -n "$suite_type" ] || continue
                observed_count=$((observed_count + 1))
              done <<<"$suite_types"
              if [ "$observed_count" -ne "$expected_count" ]; then
                printf 'truncated iteration=%s expected=%s observed=%s\\n' \\
                  "$generator_iteration" "$expected_count" "$observed_count" >&2
                wait "$noise_pid"
                exit 1
              fi
              completed_iterations=$((completed_iterations + 1))
            done

            wait "$noise_pid"
            noise_status=$?
            printf 'bash_version=%s expected_suite_types=%s completed_iterations=%s noise_subshells=10000 noise_status=%s\\n' \\
              "$BASH_VERSION" "$expected_count" "$completed_iterations" "$noise_status"
            [ "$completed_iterations" -eq 1000 ] && [ "$noise_status" -eq 0 ]
            """)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("bash_version=3.2."))
        #expect(result.output.contains("expected_suite_types="))
        #expect(result.output.contains("completed_iterations=1000"))
        #expect(result.output.contains("noise_subshells=10000 noise_status=0"))
    }

    @Test("truncated lane suite list fails with its lane and row counts")
    func truncatedLaneSuiteListFailsWithLaneAndRowCounts() async throws {
        let result = try await runLaneScriptBash(
            """
            source scripts/swift-test-helpers.sh
            swift_test_lane_suite_types() {
              printf 'OnlyOneSuite\\n'
            }
            swift_test_lane_filter_pattern large concurrent
            """)

        #expect(result.exitCode != 0)
        #expect(result.output.contains("lane suite inventory mismatch lane=large mode=concurrent"))
        #expect(result.output.contains("expected_suite_types="))
        #expect(result.output.contains("emitted_suite_types=1"))
    }
}
