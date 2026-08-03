require "rails_helper"

RSpec.describe EvidenceSnapshot, type: :model do
  describe "immutability" do
    let!(:snapshot) { create(:evidence_snapshot) }

    it "is marked read-only when loaded" do
      loaded = described_class.find(snapshot.id)
      expect(loaded).to be_readonly
    end

    it "raises when an update is attempted at the database level" do
      expect {
        described_class.where(id: snapshot.id).update_all(total_score: 1)
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it "raises when a delete is attempted at the database level" do
      expect {
        described_class.where(id: snapshot.id).delete_all
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end
  end

  describe "score integrity" do
    it "is valid when the breakdown sums to the total" do
      snapshot = build(:evidence_snapshot, total_score: 18,
        score_breakdown: [
          { "key" => "a", "name" => "A", "score" => 10, "max" => 10, "reason" => "r" },
          { "key" => "b", "name" => "B", "score" => 8, "max" => 10, "reason" => "r" }
        ])
      expect(snapshot).to be_valid
    end

    it "is invalid when the breakdown sum does not equal total" do
      snapshot = build(:evidence_snapshot, total_score: 99,
        score_breakdown: [
          { "key" => "a", "name" => "A", "score" => 10, "max" => 10, "reason" => "r" }
        ])
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:total_score].join).to include("sum")
    end
  end
end
