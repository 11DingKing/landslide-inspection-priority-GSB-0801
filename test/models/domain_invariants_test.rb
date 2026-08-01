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
  test "authoritative policy is the greatest effective_at not after captured_at" do
    old = create_policy!(version: "v1", effective_at: Time.utc(2026, 7, 1))
    new = create_policy!(version: "v2", effective_at: Time.utc(2026, 7, 20))

    assert_equal new, ScoringPolicy.authoritative_for(Time.utc(2026, 7, 25))
    assert_equal old, ScoringPolicy.authoritative_for(Time.utc(2026, 7, 10))
    assert_nil ScoringPolicy.authoritative_for(Time.utc(2026, 6, 1))
  end

  test "draft policies are never authoritative" do
    create_policy!(version: "draft-1", effective_at: Time.utc(2026, 7, 1), publish: false)
    assert_nil ScoringPolicy.authoritative_for(Time.utc(2026, 8, 1))
  end

  test "publishing two policies at the same effective_at is rejected" do
    at = Time.utc(2026, 7, 15, 8, 0, 0)
    create_policy!(version: "cand-a", effective_at: at)

    err = assert_raises(Scoring::OverlappingPolicyError) do
      create_policy!(version: "cand-b", effective_at: at)
    end
    assert_equal at, err.effective_at
    assert_equal 1, ScoringPolicy.published.where(effective_at: at).count
  end
end
