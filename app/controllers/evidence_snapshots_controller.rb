class EvidenceSnapshotsController < ApplicationController
  before_action :set_hazard_point
  before_action :set_snapshot, only: %i[show lock]

  def index
    snapshots = @hazard_point.evidence_snapshots
                             .order(snapshot_time: :desc, id: :desc)
                             .limit(200)
    render json: snapshots
  end

  def show
    render json: @snapshot
  end

  def create
    snapshot = @hazard_point.evidence_snapshots.create!(snapshot_params)
    render json: snapshot, status: :created
  end

  def lock
    @snapshot.lock!
    render json: @snapshot
  end

  private

  def set_hazard_point
    @hazard_point = HazardPoint.find(params[:hazard_point_id])
  end

  def set_snapshot
    @snapshot = @hazard_point.evidence_snapshots.find(params[:id])
  end

  def snapshot_params
    params.require(:evidence_snapshot).permit(
      :snapshot_time, :rainfall_24h_mm, :historical_event_count,
      :last_inspected_at, :road_accessible, :source_note,
      raw_payload: {}
    )
  end
end
