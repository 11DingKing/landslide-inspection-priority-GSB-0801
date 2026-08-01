# frozen_string_literal: true

require "test_helper"

class EvidenceSnapshotTest < ActiveSupport::TestCase
  test "snapshot cannot be updated through the model" do
    snapshot = build_snapshot(build_point("IMM-1"), rainfall_24h_mm: 10)
    snapshot.rainfall_24h_mm = 20
    assert_raises(ActiveRecord::RecordInvalid) { snapshot.save! }
    assert_equal 10, snapshot.reload.rainfall_24h_mm
  end

  test "database trigger rejects updates bypassing the model" do
    snapshot = build_snapshot(build_point("IMM-2"), rainfall_24h_mm: 10)
    error = assert_raises(ActiveRecord::StatementInvalid) do
      EvidenceSnapshot.where(id: snapshot.id).update_all(rainfall_24h_mm: 20)
    end
    assert_match(/immutable/, error.message)
  end

  test "database trigger rejects deletes" do
    snapshot = build_snapshot(build_point("IMM-3"))
    assert_raises(ActiveRecord::StatementInvalid) do
      EvidenceSnapshot.connection.delete("DELETE FROM evidence_snapshots WHERE id = #{snapshot.id}")
    end
  end

  test "captured_at is locked on creation" do
    captured = Time.zone.parse("2026-07-31 23:00:00")
    snapshot = build_snapshot(build_point("IMM-4"), captured_at: captured)
    assert_equal captured, snapshot.captured_at
  end
end
