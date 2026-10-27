# Property-setter generation benchmark

Multi-property setters directly construct `[]` or `[mapped]` instead of `[mapped].compact`. This avoids one Array allocation per affected call and preserves strict nil handling, value identity, and fresh mutable result arrays.

The clearest benefit is the first render of newly constructed calendars: reading an unset multi-property initializes its empty collection through the setter. This result should not be presented as a uniform speedup for all generation workloads.

- Baseline: `c926ddf3052f3bfbdeb7066d4acdeee8d3d2f03c`.
- Runtime: Ruby **4.0.9**, YJIT enabled, macOS arm64 (`arm64-darwin27`).
- Recorded on 27 October 2026. Only the property-setter optimization is compared here.

## First-render primary across four stages

All primary observations use 100-event calendars and 323 iterations per worker. Reductions below are `100 × (1 − median(candidate / baseline))` over paired observations; positive values favor the candidate.

| Stage | CPU reduction | Wall reduction | CPU wins | Allocated-object reduction |
| --- | ---: | ---: | ---: | ---: |
| Discovery | 8.37% | 9.14% | 10/10 | 23.61% |
| Confirmation | 7.67% | 7.76% | 10/10 | 23.61% |
| Diagnostic | 7.69% | 7.85% | 9/10 | 23.61% |
| Full matrix | 6.33% | 6.34% | 8/10 | 23.61% |

In the final primary, separate CPU medians were **0.680 → 0.633 ms/calendar** and wall medians **0.682 → 0.635 ms/calendar**. Their ratio is not the paired selection statistic above. Allocations fell from approximately **5,524 to 4,220 objects/calendar**, saving **1,304 objects**. The absolute first-render gain is about **0.05 ms per 100-event calendar**.

## Final 24-case matrix

`render` serializes warmed objects; `fresh` is the first render of newly built objects; `build` includes construction and rendering. CPU, wall and object reductions use the same paired-median calculation.

| Workload/mode | CPU reduction | Wall reduction | Object reduction |
| --- | ---: | ---: | ---: |
| simple/render | +0.22% | +0.34% | +0.00% |
| simple/fresh | +6.33% | +6.34% | +23.61% |
| simple/build | +2.06% | +1.84% | +7.30% |
| rich/render | +1.09% | +1.15% | +0.00% |
| rich/fresh | +2.86% | +2.82% | +9.36% |
| rich/build | -0.32% | -0.38% | +2.89% |
| escaped/render | -0.02% | +0.03% | +0.00% |
| escaped/fresh | +1.65% | +1.62% | +16.88% |
| escaped/build | +1.66% | +1.39% | +6.13% |
| ascii/render | -0.47% | -0.59% | +0.00% |
| ascii/fresh | +2.66% | +2.95% | +14.95% |
| ascii/build | -0.62% | -0.68% | +5.86% |
| unicode/render | +0.52% | +0.38% | +0.00% |
| unicode/fresh | +0.95% | +1.13% | +2.00% |
| unicode/build | -0.43% | -0.45% | +1.65% |
| parameters/render | +0.08% | +0.43% | +0.00% |
| parameters/fresh | +2.79% | +2.64% | +9.04% |
| parameters/build | +0.60% | +0.57% | +3.94% |
| recurrence/render | +0.85% | +0.85% | +0.00% |
| recurrence/fresh | +4.56% | +4.81% | +12.40% |
| recurrence/build | +3.27% | +3.29% | +4.07% |
| timezone/render | +3.82% | +9.54% | +0.00% |
| timezone/fresh | +5.61% | +5.75% | +21.26% |
| timezone/build | +3.19% | +3.08% | +6.67% |

No final guard point estimate exceeded a 3% median slowdown; the largest slowdowns were **0.623% CPU and 0.682% wall**, both for `ascii/build`. These point estimates are not a formal demonstration that every true regression is smaller than 3%. Warmed-render variation should not be interpreted as a direct setter-call benefit after the collections have already been initialized.

## Measurement method

- Ten adjacent baseline/candidate pairs per case, alternating AB/BA order, with five pairs in each order. Each worker starts a fresh Ruby process for one library, workload and mode.
- Forty warmups precede measurement. Baseline calibration targets roughly 0.2 seconds, bounded to 20–500 iterations. Counts are fixed within pairs and reused across later stages.
- CPU and monotonic wall time are measured with GC enabled. Fresh-calendar and retained-output batches are bounded to 16. Construction is outside the `fresh` timer; it is included in `build`.
- Every timed output is checked outside timing. Source digests, runtime configuration and output identity are verified. No observations or outliers were removed.
- [Raw paired observations](results/property_setter-ruby-4.0.9-yjit.tsv) contain **450 property-only pairs** across the four stages. Time and allocation columns are worker totals; divide by `iterations` for per-calendar values. The TSV is an unaltered copy of the recorded observations.

## Interpreting the final 8/10 result

The original experiment required at least 9/10 CPU wins, in addition to 3% paired median CPU and wall reductions. The final property-only primary had 8/10 wins, so it did not pass that engineering consistency rule. Its median gains passed both magnitude thresholds and every final guard point estimate stayed below the slowdown limit.

This PR reassesses that binary rule using the repeated 6–8% first-render median gains, the allocation reduction, API compatibility and the small implementation scope. The final two losses remain in the data: one was 7.87% slower, the other 0.35% slower. Across all four stages there were 37/40 CPU wins; this is descriptive evidence, not a pooled confirmatory hypothesis test. The change is being retained on that broader practical assessment, not represented as having passed the original 9/10 gate.

The later property-only full matrix was added after earlier experiment outcomes. That post hoc extension and sequential candidate selection limit formal inference from pooling stages. CPU/wall dependence, machine variability, multiple guard comparisons and the lack of measurements on other Ruby versions or platforms also limit generalization. Allocated-object counts do not measure peak memory.

Independent reviews by Claude and agy recommended retaining the property change. DeepSeek characterized the heuristic result as inconclusive while favoring retention for first-render workflows. Their recommendations support reassessment; they do not substitute for the measurements or establish statistical certainty.

## Reproduction

Use Ruby 4.0.9 in a clean checkout of this branch. The [dependency snapshot](results/property_setter_dependencies.lock) records the measured versions; copy it to `Gemfile.lock` before `bundle install`. The following command replays the final standalone matrix with the recorded per-case iteration counts. It produces fresh raw measurements rather than reusing the recorded timing results.

```sh
export ICALENDAR_BASELINE_DIR=$(mktemp -d)
export ICALENDAR_MANIFEST=$(mktemp)
export ICALENDAR_RESULTS=$(mktemp)
git archive c926ddf3052f3bfbdeb7066d4acdeee8d3d2f03c lib | tar -x -C "$ICALENDAR_BASELINE_DIR"
bundle exec ruby -rjson <<'RUBY'
header, *values = File.readlines('benchmarks/results/property_setter-ruby-4.0.9-yjit.tsv', chomp: true).map { |line| line.split("\t") }
rows = values.map { |row| header.zip(row).to_h }
counts = rows.select { |row| row['stage'] == 'properties-final' }.to_h do |row|
  [row['case'], Integer(row['iterations'])]
end
manifest = {
  baseline: { lib: File.join(ENV.fetch('ICALENDAR_BASELINE_DIR'), 'lib') },
  variants: { properties: { lib: File.expand_path('lib'), cases: counts.keys } },
  iterations: counts
}
File.write(ENV.fetch('ICALENDAR_MANIFEST'), JSON.pretty_generate(manifest))
RUBY
RUBYOPT=--yjit EXPECTED_RUBY=4.0.9 REQUIRE_YJIT=1 \
  EVENTS=100 SAMPLES=10 WARMUP=40 TARGET_SECONDS=0.2 SEED=27105 \
  MANIFEST="$ICALENDAR_MANIFEST" JSON_OUTPUT="$ICALENDAR_RESULTS" \
  bundle exec ruby benchmarks/generation_isolation.rb
```

`generation_isolation.rb` uses the fixtures in `generation_comparison.rb`. It validates library origins, runtime identity and every generated output. The JSON output records all pairs and source hashes. Preserve all observations and keep other CPU-heavy work separate from timing. An independent machine or run may produce different timings; this recipe does not certify any particular threshold.
