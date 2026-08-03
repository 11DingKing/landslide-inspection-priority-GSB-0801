# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    RULES_V1 = {
      "rainfall_24h" => {
        "thresholds" => [
          { "gte_mm" => 150, "score" => 40 },
          { "gte_mm" => 100, "score" => 30 },
          { "gte_mm" => 50,  "score" => 20 },
          { "gte_mm" => 25,  "score" => 10 }
        ]
      },
      "historical_events" => { "per_event" => 15, "cap_events" => 2 },
      "inspection_recency" => {
        "never" => 30,
        "stale_days" => [
          { "gte_days" => 90, "score" => 25 },
          { "gte_days" => 30, "score" => 15 },
          { "gte_days" => 7,  "score" => 5 }
        ],
        "fresh" => 0
      },
      "risk_levels" => [
        { "min_total" => 70, "level" => "high" },
        { "min_total" => 40, "level" => "medium" }
      ]
    }.freeze

    def build_strategy(version:, rules: RULES_V1, from: Time.zone.parse("2026-01-01"), to: nil, status: "draft")
      StrategyVersion.create!(
        version: version,
        rules: rules,
        status: status,
        effective_range: StrategyVersion.compose_range(from, to)
      )
    end

    def build_point(code)
      HazardPoint.create!(external_code: code, name: code, kind: "registered_hazard")
    end

    def build_snapshot(point, captured_at: Time.current, **attrs)
      point.evidence_snapshots.create!({
        rainfall_24h_mm: 0, historical_event_count: 0,
        road_accessible: true, captured_at: captured_at
      }.merge(attrs))
    end

    # Test cleanup must temporarily lift the immutability trigger; production
    # code paths can never do this accidentally.
    def clean_tables!
      QueueSnapshotEntry.delete_all
      QueueSnapshot.delete_all
      ScoreRecord.delete_all
      EvidenceSnapshot.connection.execute(
        "ALTER TABLE evidence_snapshots DISABLE TRIGGER evidence_snapshots_no_update"
      )
      EvidenceSnapshot.delete_all
      HazardPoint.delete_all
      StrategyVersion.delete_all
    ensure
      EvidenceSnapshot.connection.execute(
        "ALTER TABLE evidence_snapshots ENABLE TRIGGER evidence_snapshots_no_update"
      )
    end
  end
end
