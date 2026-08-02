require "rails_helper"

RSpec.describe "Strategy version boundary and replay", type: :request do
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let(:v1_effective) { Time.utc(2026, 1, 1, 0, 0, 0) }

  let!(:v1) do
    create(:scoring_strategy,
           version_code: "v1.0-baseline",
           effective_at: v1_effective,
           published_at: v1_effective)
  end

  let!(:v2) do
    create(:scoring_strategy,
           version_code: "v2.0-refined",
           effective_at: boundary,
           published_at: boundary)
  end

  let(:rds) { create(:hazard_point, :road_slope, :blocked, external_code: "RDS-002", name: "RDS-002") }

  it "binds pre-boundary snapshots to v1 and boundary snapshots to v2" do
    old_snap = create(:evidence_snapshot,
                      hazard_point: rds,
                      snapshot_time: boundary - 6.hours,
                      rainfall_24h_mm: 112,
                      historical_event_count: 0,
                      last_inspected_at: boundary - 70.hours,
                      road_accessible: false)
    boundary_snap = create(:evidence_snapshot,
                           hazard_point: rds,
                           snapshot_time: boundary,
                           rainfall_24h_mm: 210,
                           historical_event_count: 0,
                           last_inspected_at: boundary - 70.hours,
                           road_accessible: false)

    old_score = Scoring::PriorityComputer.call(old_snap, now: Time.current)
    new_score = Scoring::PriorityComputer.call(boundary_snap, now: Time.current)

    expect(old_score.scoring_strategy_id).to eq(v1.id)
    expect(old_score.explanation["version_code"]).to eq("v1.0-baseline")

    expect(new_score.scoring_strategy_id).to eq(v2.id)
    expect(new_score.explanation["version_code"]).to eq("v2.0-refined")
  end

  it "keeps v1 replayable: old snapshot can be replayed against v1 explicitly" do
    old_snap = create(:evidence_snapshot,
                      hazard_point: rds,
                      snapshot_time: boundary - 6.hours,
                      rainfall_24h_mm: 112,
                      road_accessible: false)

    original = Scoring::PriorityComputer.call(old_snap, now: Time.current)
    replayed = Scoring::PriorityComputer.call(
      old_snap, strategy: v1, now: Time.current
    )

    expect(replayed.id).to eq(original.id)
    expect(replayed.total_score).to eq(original.total_score)
    expect(replayed.explanation["version_code"]).to eq("v1.0-baseline")
  end

  it "does not retire v1 when v2 is published; both remain selectable by time" do
    expect(Scoring::StrategySelector.for_time(boundary - 1).id).to eq(v1.id)
    expect(Scoring::StrategySelector.for_time(boundary).id).to eq(v2.id)
    expect(Scoring::StrategySelector.for_time(boundary + 1.day).id).to eq(v2.id)
  end

  it "road blockage only affects dispatch_status, not total_score or risk_level" do
    snap = create(:evidence_snapshot,
                  hazard_point: rds,
                  snapshot_time: boundary,
                  rainfall_24h_mm: 210,
                  historical_event_count: 0,
                  last_inspected_at: boundary - 70.hours,
                  road_accessible: false)
    score = Scoring::PriorityComputer.call(snap, now: Time.current)

    open_point = create(:hazard_point, :road_slope, road_accessible: true)
    open_snap = create(:evidence_snapshot,
                       hazard_point: open_point,
                       snapshot_time: boundary,
                       rainfall_24h_mm: 210,
                       historical_event_count: 0,
                       last_inspected_at: boundary - 70.hours,
                       road_accessible: true)
    open_score = Scoring::PriorityComputer.call(open_snap, now: Time.current)

    expect(score.total_score).to eq(open_score.total_score)
    expect(score.risk_level).to eq(open_score.risk_level)
    expect(score.dispatch_status).to eq("blocked")
    expect(open_score.dispatch_status).to eq("available")
  end

  it "concurrent computation of the same snapshot+strategy leaves one row" do
    snap = create(:evidence_snapshot,
                  hazard_point: rds,
                  snapshot_time: boundary,
                  rainfall_24h_mm: 210,
                  road_accessible: false)

    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Scoring::PriorityComputer.call(EvidenceSnapshot.find(snap.id), now: Time.current)
        end
      end
    end
    rows = threads.map(&:value)
    expect(rows.map(&:id).uniq.size).to eq(1)
    expect(PriorityScore.where(evidence_snapshot_id: snap.id,
                               scoring_strategy_id: v2.id).count).to eq(1)
  end

  it "POST /hazard_points/:hp/evidence_snapshots with same business_key is idempotent; different payload returns 409" do
    payload = {
      evidence_snapshot: {
        snapshot_time: boundary.iso8601,
        rainfall_24h_mm: 210,
        historical_event_count: 0,
        last_inspected_at: (boundary - 70.hours).iso8601,
        road_accessible: false,
        business_key: "evidence-rds-002-20260802-0000",
        source_note: "boundary"
      }
    }

    post "/hazard_points/#{rds.id}/evidence_snapshots",
         params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:created)
    first = JSON.parse(response.body)

    post "/hazard_points/#{rds.id}/evidence_snapshots",
         params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    second = JSON.parse(response.body)
    expect(second["id"]).to eq(first["id"])

    conflict = payload.dup
    conflict[:evidence_snapshot] = payload[:evidence_snapshot].merge(rainfall_24h_mm: 300)
    post "/hazard_points/#{rds.id}/evidence_snapshots",
         params: conflict.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:conflict)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("payload_conflict")
    expect(body["business_key"]).to eq("evidence-rds-002-20260802-0000")
    expect(body["existing_snapshot_id"]).to eq(first["id"])
  end
end
