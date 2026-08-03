require "rails_helper"

RSpec.describe Scoring::SnapshotUpserter do
  let(:point) { create(:hazard_point, :road_slope, :blocked) }
  let(:base_attrs) do
    {
      snapshot_time: Time.utc(2026, 8, 1, 18, 0, 0),
      rainfall_24h_mm: 112.0,
      historical_event_count: 0,
      last_inspected_at: Time.utc(2026, 7, 29, 15, 0, 0),
      road_accessible: false,
      source_note: "original",
      raw_payload: { source: "test" }
    }
  end

  it "creates a new snapshot when business_key is absent" do
    result = described_class.call(point, base_attrs)
    expect(result.created?).to be true
    expect(EvidenceSnapshot.count).to eq(1)
  end

  it "is idempotent: same business_key + same payload returns existing row" do
    r1 = described_class.call(point, base_attrs.merge(business_key: "BK-1"))
    r2 = described_class.call(point, base_attrs.merge(business_key: "BK-1"))
    expect(r1.snapshot.id).to eq(r2.snapshot.id)
    expect(r2.created?).to be false
    expect(EvidenceSnapshot.where(business_key: "BK-1").count).to eq(1)
  end

  it "rejects same business_key with DIFFERENT payload (409 payload_conflict)" do
    described_class.call(point, base_attrs.merge(business_key: "BK-2"))
    expect {
      described_class.call(point, base_attrs.merge(
        business_key: "BK-2",
        rainfall_24h_mm: 210.0
      ))
    }.to raise_error(Scoring::SnapshotUpserter::PayloadConflict) { |e|
      expect(e.existing.business_key).to eq("BK-2")
      expect(e.existing.rainfall_24h_mm.to_f).to eq(112.0)
    }
    expect(EvidenceSnapshot.where(business_key: "BK-2").count).to eq(1)
  end

  it "handles concurrent inserts with same business_key as idempotent" do
    attrs = base_attrs.merge(business_key: "BK-CONC")

    threads = 6.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            described_class.call(HazardPoint.find(point.id), attrs)
          rescue Scoring::SnapshotUpserter::PayloadConflict
            :conflict
          end
        end
      end
    end

    results = threads.map(&:value)
    ids = results.filter_map { |r| r.respond_to?(:snapshot) ? r.snapshot.id : nil }
    expect(ids.uniq.size).to eq(1)
    expect(EvidenceSnapshot.where(business_key: "BK-CONC").count).to eq(1)
  end

  it "does not treat road_accessible change as a conflict when nil resolves to same value" do
    attrs_with_nil = base_attrs.merge(business_key: "BK-3", road_accessible: nil)
    r1 = described_class.call(point, attrs_with_nil)
    # The snapshot captured road_accessible=false from the point. Now the
    # caller explicitly sends false; signatures should match.
    r2 = described_class.call(point, base_attrs.merge(business_key: "BK-3"))
    expect(r1.snapshot.id).to eq(r2.snapshot.id)
  end
end
