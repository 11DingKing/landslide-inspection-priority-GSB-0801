require "test_helper"

class Scoring::MaterializerTest < ActiveSupport::TestCase
  setup do
    @policy = create_policy!(version: "mat-v1", effective_from: Time.utc(2026, 7, 1))
  end

  test "materialises an explainable score whose components sum to total" do
    point = create_point!(code: "MAT-1", category: "cut_slope_housing")
    snap = create_snapshot!(point, captured_at: Time.utc(2026, 7, 10), rainfall: 186, history: 2)

    ps = Scoring::Materializer.new(snap).call.priority_score
    assert_equal ps.total_score,
                 ps.rainfall_score + ps.history_score + ps.recency_score + ps.exposure_score
    assert_equal "extreme", ps.risk_level
  end

  test "road closed marks scheduling blocked without lowering risk" do
    point = create_point!(code: "MAT-BLOCK", category: "road_slope")
    snap = create_snapshot!(point, captured_at: Time.utc(2026, 7, 10),
                            rainfall: 112, history: 0, road_accessible: false,
                            last_inspected_at: Time.utc(2026, 7, 10) - 400 * 86_400)
    ps = Scoring::Materializer.new(snap).call.priority_score

    assert_equal "blocked", ps.scheduling_status
    assert_operator ps.total_score, :>, 0
    assert_equal "moderate", ps.risk_level
  end

  test "concurrent computation of the same snapshot converges to one row" do
    point = create_point!(code: "MAT-RACE", category: "cut_slope_housing")
    snap = create_snapshot!(point, captured_at: Time.utc(2026, 7, 10), rainfall: 186, history: 2)

    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Scoring::Materializer.new(snap).call
        end
      end
    end
    threads.each(&:join)

    scores = PriorityScore.where(evidence_snapshot_id: snap.id, scoring_policy_id: @policy.id)
    assert_equal 1, scores.count, "expected exactly one converged row"
  end

  test "an old snapshot replays deterministically against its historical policy" do
    point = create_point!(code: "MAT-REPLAY", category: "registered_hazard")
    snap = create_snapshot!(point, captured_at: Time.utc(2026, 7, 10), rainfall: 95, history: 1,
                            last_inspected_at: Time.utc(2026, 7, 10))

    first = Scoring::Materializer.new(snap).call(policy: @policy).priority_score.total_score

    # Bound v1 and publish a successor from the boundary. v1 stays published, so
    # replaying the old snapshot against the pinned v1 reproduces the original
    # numbers exactly, even though a radically different v2 now exists.
    @policy.bound!(Time.utc(2026, 8, 1))
    create_policy!(version: "mat-v2", effective_from: Time.utc(2026, 8, 1),
                   definition: build_baseline_definition.merge(
                     "rainfall" => { "thresholds" => [[0, 40]] } # radically different
                   ))

    replayed = Scoring::Materializer.new(snap).call(policy: @policy).priority_score.total_score
    assert_equal first, replayed
  end
end

class Scoring::QueueTest < ActiveSupport::TestCase
  setup do
    @policy = create_policy!(version: "queue-v1", effective_from: Time.utc(2026, 7, 1))
  end

  # Bulk-create real hazard points + snapshots (to satisfy FKs), then attach a
  # priority row per snapshot with the requested total. Returns nothing; rows
  # are queryable via the queue afterwards. `totals` maps an ordinal position
  # to a total_score so we can craft ties deliberately.
  def insert_scores!(count:, prefix:, total_for:)
    now = Time.current
    point_rows = (1..count).map do |i|
      { code: "#{prefix}-#{i}", name: "p#{i}", category: "registered_hazard",
        created_at: now, updated_at: now }
    end
    HazardPoint.insert_all!(point_rows)
    point_ids = HazardPoint.where("code LIKE ?", "#{prefix}-%").order(:id).pluck(:id)

    snap_rows = point_ids.map do |hp_id|
      { hazard_point_id: hp_id, captured_at: now, rainfall_mm_24h: 0,
        historical_event_count: 0, road_accessible: true,
        content_digest: "seed-#{hp_id}", created_at: now, updated_at: now }
    end
    EvidenceSnapshot.insert_all!(snap_rows)
    snap_ids = EvidenceSnapshot.where(hazard_point_id: point_ids).order(:hazard_point_id).pluck(:id, :hazard_point_id)

    score_rows = snap_ids.each_with_index.map do |(snap_id, hp_id), idx|
      total = total_for.call(idx + 1, hp_id)
      rainfall = [total, 40].min
      rem = total - rainfall
      history = [rem, 25].min
      rem -= history
      recency = [rem, 20].min
      rem -= recency
      exposure = [rem, 15].min
      {
        evidence_snapshot_id: snap_id, scoring_policy_id: @policy.id, hazard_point_id: hp_id,
        rainfall_score: rainfall, history_score: history, recency_score: recency,
        exposure_score: exposure, total_score: rainfall + history + recency + exposure,
        risk_level: "low", scheduling_status: "schedulable",
        policy_version: @policy.version, evidence_captured_at: now,
        created_at: now, updated_at: now
      }
    end
    PriorityScore.insert_all!(score_rows)
  end

  test "orders at least 10k points by total desc then hazard_point_id asc" do
    insert_scores!(count: 10_000, prefix: "BULK", total_for: ->(ordinal, _hp) { ordinal % 100 })

    all = []
    cursor = nil
    loop do
      page = Scoring::Queue.new(policy: @policy).page(limit: 1_000, cursor: cursor)
      all.concat(page.records)
      cursor = page.next_cursor
      break if cursor.nil?
    end

    assert_equal 10_000, all.size
    pairs = all.map { |r| [r.total_score, r.hazard_point_id] }
    assert_equal pairs.sort_by { |t, id| [-t, id] }, pairs, "queue not in stable order"
    assert_equal all.map(&:hazard_point_id).uniq.size, all.size, "duplicate rows across pages"
  end

  test "pagination is stable when equal-scored rows are written continuously" do
    # Seed a page worth of tied scores.
    insert_scores!(count: 50, prefix: "TIE-A", total_for: ->(_o, _hp) { 42 })

    q = Scoring::Queue.new(policy: @policy)
    first = q.page(limit: 10)
    first_ids = first.records.map(&:hazard_point_id)

    # New equal-scored rows arrive between page fetches, all with larger ids.
    insert_scores!(count: 50, prefix: "TIE-B", total_for: ->(_o, _hp) { 42 })

    second = q.page(limit: 10, cursor: first.next_cursor)
    second_ids = second.records.map(&:hazard_point_id)

    # No overlap and no backward jump: every id on page 2 is strictly greater
    # than the last id of page 1 (same tied score), so page 1 never reshuffles.
    assert (first_ids & second_ids).empty?, "pages overlapped"
    assert_operator second_ids.min, :>, first_ids.max
  end

  test "default page returns all rows (no limit collapses to one)" do
    insert_scores!(count: 25, prefix: "DEFLIM", total_for: ->(o, _hp) { o % 50 })
    page = Scoring::Queue.new(policy: @policy).page
    assert_equal 25, page.records.size
    assert_nil page.next_cursor
  end

  test "filtering by scheduling_status does not alter risk data" do
    point = create_point!(code: "Q-BLOCK", category: "road_slope")
    snap = create_snapshot!(point, captured_at: Time.utc(2026, 7, 10), rainfall: 112,
                            road_accessible: false, last_inspected_at: Time.utc(2026, 7, 10) - 400 * 86_400)
    Scoring::Materializer.new(snap).call(policy: @policy)

    blocked = Scoring::Queue.new(policy: @policy).page(scheduling_status: "blocked")
    assert_equal 1, blocked.records.size
    assert_equal "moderate", blocked.records.first.risk_level
  end
end

class Scoring::ConcurrentPublishTest < ActiveSupport::TestCase
  test "two candidates racing to publish overlapping intervals yield one winner" do
    from = Time.utc(2026, 7, 15, 9, 0, 0)
    # Both candidates claim the same open-ended window, so at most one can be
    # published; the interval-overlap exclusion constraint rejects the other.
    a = create_policy!(version: "race-a", effective_from: from, publish: false)
    b = create_policy!(version: "race-b", effective_from: from, publish: false)

    results = Queue.new # thread-safe collector
    [a, b].map do |policy|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          policy.publish!
          results << :ok
        rescue Scoring::OverlappingPolicyError
          results << :rejected
        end
      end
    end.each(&:join)

    outcomes = Array.new(results.size) { results.pop }
    assert_equal 1, ScoringPolicy.published.count
    assert_includes outcomes, :rejected
  end
end
