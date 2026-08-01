# frozen_string_literal: true

class QueueSnapshotEntry < ApplicationRecord
  belongs_to :queue_snapshot
  belongs_to :score_record
end
