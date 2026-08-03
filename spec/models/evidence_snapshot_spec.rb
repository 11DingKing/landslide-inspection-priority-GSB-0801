require "rails_helper"

RSpec.describe EvidenceSnapshot do
  let(:point) { create(:hazard_point) }

  it "can be edited until locked" do
    snap = create(:evidence_snapshot, hazard_point: point, rainfall_24h_mm: 50)
    snap.update!(rainfall_24h_mm: 80)
    expect(snap.reload.rainfall_24h_mm.to_f).to eq(80)
  end

  it "cannot be edited after lock!" do
    snap = create(:evidence_snapshot, hazard_point: point, rainfall_24h_mm: 50)
    snap.lock!
    expect(snap.reload.immutable).to be true
    expect { snap.update!(rainfall_24h_mm: 80) }
      .to raise_error(ActiveRecord::RecordNotSaved)
    expect(snap.reload.rainfall_24h_mm.to_f).to eq(50)
  end

  it "copies road_accessible from hazard point when not provided" do
    blocked = create(:hazard_point, :blocked)
    snap = create(:evidence_snapshot, hazard_point: blocked,
                                      road_accessible: nil)
    expect(snap.reload.road_accessible).to be false
  end

  it "locks through the controller lock! method" do
    snap = create(:evidence_snapshot, hazard_point: point)
    snap.lock!
    expect(snap.reload.immutable).to be true
    expect { snap.update!(rainfall_24h_mm: 999) }
      .to raise_error(ActiveRecord::RecordNotSaved)
  end
end
