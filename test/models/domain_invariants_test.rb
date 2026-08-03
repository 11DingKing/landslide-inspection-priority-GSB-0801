require "test_helper"

class EvidenceSnapshotTest < ActiveSupport::TestCase
  setup { @point = create_point!(code: "IMM-1") }

  test "snapshot is immutable after creation" do
    snap = create_snapshot!(@point, rainfall: 100)
    snap.rainfall_mm_24h = 200
    assert_raises(ActiveRecord::RecordNotSaved) { snap.save! }
    assert_equal BigDecimal("100"), snap.reload.rainfall_mm_24h
  end

  test "snapshot cannot be destroyed" do
    snap = create_snapshot!(@point, rainfall: 100)
    assert_equal false, snap.destroy
    assert EvidenceSnapshot.exists?(snap.id)
  end

  test "content digest is deterministic and freezes the facts" do
    at = Time.utc(2026, 8, 1, 0, 0, 0)
    snap = create_snapshot!(@point, captured_at: at, rainfall: 123.45, history: 2, road_accessible: false)
    expected = EvidenceSnapshot.digest_for(
      hazard_point_id: @point.id, captured_at: at, rainfall_mm_24h: 123.45,
      historical_event_count: 2, road_accessible: false, point_last_inspected_at: nil
    )
    assert_equal expected, snap.content_digest
  end
end

class ScoringPolicySelectionTest < ActiveSupport::TestCase
  test "authoritative policy is the one whose interval contains captured_at" do
    v1 = create_policy!(version: "v1", effective_from: Time.utc(2026, 1, 1),
                        effective_until: Time.utc(2026, 8, 2))
    v2 = create_policy!(version: "v2", effective_from: Time.utc(2026, 8, 2))

    assert_equal v1, ScoringPolicy.authoritative_for(Time.utc(2026, 7, 10))
    # Half-open [from, until): the boundary instant belongs to v2, not v1.
    assert_equal v2, ScoringPolicy.authoritative_for(Time.utc(2026, 8, 2))
    assert_equal v2, ScoringPolicy.authoritative_for(Time.utc(2026, 9, 1))
    assert_nil ScoringPolicy.authoritative_for(Time.utc(2025, 12, 31))
  end

  test "draft policies are never authoritative" do
    create_policy!(version: "draft-1", effective_from: Time.utc(2026, 7, 1), publish: false)
    assert_nil ScoringPolicy.authoritative_for(Time.utc(2026, 8, 1))
  end

  test "publishing a policy whose interval overlaps a published one is rejected" do
    create_policy!(version: "cand-a", effective_from: Time.utc(2026, 1, 1),
                   effective_until: Time.utc(2026, 8, 2))

    assert_raises(Scoring::OverlappingPolicyError) do
      # Overlaps [2026-01-01, 2026-08-02) on the 2026-07 window.
      create_policy!(version: "cand-b", effective_from: Time.utc(2026, 7, 1),
                     effective_until: Time.utc(2026, 9, 1))
    end
    assert_equal 1, ScoringPolicy.published.count
  end

  test "bounding a published policy lets a successor start without retiring it" do
    v1 = create_policy!(version: "adj-v1", effective_from: Time.utc(2026, 1, 1))
    # Adjacent successor would overlap the open-ended v1 until v1 is bounded.
    assert_raises(Scoring::OverlappingPolicyError) do
      create_policy!(version: "adj-v2", effective_from: Time.utc(2026, 8, 2))
    end

    v1.bound!(Time.utc(2026, 8, 2))
    v2 = create_policy!(version: "adj-v2b", effective_from: Time.utc(2026, 8, 2))

    # v1 is still published and still authoritative for its (now bounded) window.
    assert v1.reload.published?
    assert_equal v1, ScoringPolicy.authoritative_for(Time.utc(2026, 6, 1))
    assert_equal v2, ScoringPolicy.authoritative_for(Time.utc(2026, 8, 2))
  end
end
