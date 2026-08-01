# frozen_string_literal: true

# Computes (or replays) the priority score of one evidence snapshot and
# persists it as a ScoreRecord.
#
# Idempotent and safe under concurrency: the unique index
# idx_score_records_snapshot_strategy makes duplicate inserts impossible;
# concurrent workers either insert the same deterministic values or adopt the
# row that won the race. The scoring itself is a pure function, so a replay
# of an old snapshot under its original strategy version reproduces the
# original record exactly.
class PriorityCalculator
  class NoApplicableStrategy < StandardError; end

  # snapshot:        the immutable evidence to score.
  # strategy_version: nil  -> the published version effective at
  #                         snapshot.captured_at (original decision replay);
  #                   else -> explicit version (comparative replay).
  def self.call(snapshot:, strategy_version: nil)
    strategy_version ||= StrategyVersion.applicable_to(snapshot.captured_at)
    raise NoApplicableStrategy, "no published strategy covers #{snapshot.captured_at.iso8601}" if strategy_version.nil?

    existing = ScoreRecord.find_by(evidence_snapshot: snapshot, strategy_version: strategy_version)
    return existing if existing

    result = Scoring::Engine.score(evidence: snapshot.evidence, rules: strategy_version.rules)

    attempts = 0
    begin
      ScoreRecord.transaction do
        # Clear the current flag BEFORE inserting so the partial unique index
        # (one current score per hazard point) is never violated.
        ScoreRecord.where(hazard_point: snapshot.hazard_point, is_current: true)
                   .update_all(is_current: false)
        ScoreRecord.create!(
          hazard_point: snapshot.hazard_point,
          evidence_snapshot: snapshot,
          strategy_version: strategy_version,
          components: result.components,
          total_score: result.total_score,
          risk_level: result.risk_level,
          scheduling_status: result.scheduling_status,
          is_current: true,
          computed_at: Time.current
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # A concurrent worker won a race (same snapshot+strategy, or another
      # snapshot of the same point). Its transaction has committed by the
      # time PostgreSQL reports the conflict; re-read and, if our exact row
      # exists, adopt it (deterministic engine => identical values), else
      # retry the insert.
      attempts += 1
      raise if attempts > 3

      winner = ScoreRecord.find_by(evidence_snapshot: snapshot, strategy_version: strategy_version)
      return winner if winner

      retry
    end
  end
end
