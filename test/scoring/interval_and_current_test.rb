require "test_helper"

# Tests for the interval/business-key/current-score evolution.
class BusinessKeyIdempotencyTest < ActiveSupport::TestCase
  setup { @point = create_point!(code: "BK-MODEL") }

  def facts(overrides = {})
    { captured_at: Time.utc(2026, 7, 10), rainfall_mm_24h: 95,
      historical_event_count: 1, road_accessible: true }.merge(overrides)
  end

  test "same business_key + same payload returns the same snapshot" do
    a = EvidenceSnapshot.capture!(hazard_point: @point, business_key: "k1", **facts)
    b = EvidenceSnapshot.capture!(hazard_point: @point, business_key: "k1", **facts)
    assert_equal a.id, b.id
    assert_equal 1, EvidenceSnapshot.where(business_key: "k1").count
  end

  test "same business_key + different payload raises a conflict" do
    EvidenceSnapshot.capture!(hazard_point: @point, business_key: "k2", **facts)
    err = assert_raises(Scoring::ConflictingBusinessKeyError) do
      EvidenceSnapshot.capture!(hazard_point: @point, business_key: "k2", **facts(rainfall_mm_24h: 200))
    end
    assert_equal "k2", err.business_key
  end

  test "no business_key always creates a new snapshot" do
    a = EvidenceSnapshot.capture!(hazard_point: @point, **facts)
    b = EvidenceSnapshot.capture!(hazard_point: @point, **facts)
    refute_equal a.id, b.id
  end

  test "concurrent capture with same key and payload converges to one snapshot" do
    threads = 6.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          EvidenceSnapshot.capture!(hazard_point: @point, business_key: "krace", **facts)
        rescue Scoring::ConflictingBusinessKeyError
          nil
        end
      end
    end
    threads.each(&:join)
    assert_equal 1, EvidenceSnapshot.where(business_key: "krace").count
  end
end

class CurrentScoreTest < ActiveSupport::TestCase
  setup do
    @v1 = create_policy!(version: "cur-v1", effective_from: Time.utc(2026, 1, 1),
                         effective_until: Time.utc(2026, 8, 2))
    @v2 = create_policy!(version: "cur-v2", effective_from: Time.utc(2026, 8, 2))
    @point = create_point!(code: "CUR-1", category: "road_slope")
  end

  test "latest snapshot's score becomes current; older score stays but loses current" do
    old = create_snapshot!(@point, captured_at: Time.utc(2026, 7, 10), rainfall: 112, road_accessible: false,
                           last_inspected_at: Time.utc(2025, 6, 1))
    old_score = Scoring::Materializer.new(old).call.priority_score
    assert old_score.reload.current
    assert_equal "cur-v1", old_score.policy_version

    newer = create_snapshot!(@point, captured_at: Time.utc(2026, 8, 2), rainfall: 210, road_accessible: false,
                             last_inspected_at: Time.utc(2025, 6, 1))
    new_score = Scoring::Materializer.new(newer).call.priority_score

    assert new_score.reload.current
    refute old_score.reload.current
    assert_equal "cur-v2", new_score.policy_version
    # Exactly one current per point.
    assert_equal 1, PriorityScore.where(hazard_point_id: @point.id, current: true).count
    # Blocked road: scheduling only, risk preserved and non-zero.
    assert_equal "blocked", new_score.scheduling_status
    assert_operator new_score.total_score, :>, 0
  end

  test "replaying an older snapshot never steals current from the latest" do
    old = create_snapshot!(@point, captured_at: Time.utc(2026, 7, 10), rainfall: 112, road_accessible: false)
    newer = create_snapshot!(@point, captured_at: Time.utc(2026, 8, 2), rainfall: 210, road_accessible: false)
    Scoring::Materializer.new(old).call
    new_score = Scoring::Materializer.new(newer).call.priority_score

    # Audit replay of the old snapshot again.
    old_score = Scoring::Materializer.new(old).call.priority_score

    refute old_score.reload.current
    assert new_score.reload.current
  end

  test "concurrent computation of one snapshot leaves exactly one current row" do
    snap = create_snapshot!(@point, captured_at: Time.utc(2026, 8, 2), rainfall: 210, road_accessible: false)
    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Scoring::Materializer.new(snap).call
        end
      end
    end
    threads.each(&:join)

    assert_equal 1, PriorityScore.where(evidence_snapshot_id: snap.id).count
    assert_equal 1, PriorityScore.where(hazard_point_id: @point.id, current: true).count
  end
end
