class ScoringEngine
  class Error < StandardError; end
  class InvalidRules < Error; end

  Result = Struct.new(:total_score, :score_breakdown, :risk_level,
                      :dispatch_status, :explanation, keyword_init: true)

  attr_reader :strategy

  def initialize(strategy)
    @strategy = strategy
    @rules = strategy.rules
    validate_rules!
  end

  def score(evidence)
    breakdown = @rules["items"].map { |item| evaluate_item(item, evidence) }

    total = breakdown.sum { |entry| entry[:score] }

    risk_level = resolve_risk_level(total)

    road_blocked = evidence[:road_status].to_s == "closed"
    dispatch_status = road_blocked ? "blocked" : "schedulable"

    explanation = build_explanation(breakdown, total, risk_level,
                                    dispatch_status, road_blocked)

    Result.new(
      total_score: total,
      score_breakdown: breakdown,
      risk_level: risk_level,
      dispatch_status: dispatch_status,
      explanation: explanation
    )
  end

  private

  def validate_rules!
    unless @rules.is_a?(Hash) && @rules["items"].is_a?(Array)
      raise InvalidRules, "rules must contain an items array"
    end
  end

  def evaluate_item(item, evidence)
    raw_score =
      case item["type"]
      when "numeric_tier" then score_numeric_tier(item, evidence)
      when "categorical" then score_categorical(item, evidence)
      when "inspection_recency" then score_inspection_recency(item, evidence)
      else
        raise InvalidRules, "unknown item type: #{item['type'].inspect}"
      end

    score = raw_score.to_i.clamp(0, item["max"].to_i)

    {
      key: item["key"],
      name: item["name"],
      score: score,
      max: item["max"].to_i,
      reason: reason_for(item, evidence, score)
    }
  end

  def score_numeric_tier(item, evidence)
    value = evidence.fetch(item["field"].to_sym).to_f
    tier = item["tiers"].find do |t|
      value >= t["min"].to_f && (t["max"].nil? || value < t["max"].to_f)
    end
    raise InvalidRules, "no tier matched for #{item['key']}=#{value}" if tier.nil?

    tier["score"].to_i
  end

  def score_categorical(item, evidence)
    value = evidence.fetch(item["field"].to_sym).to_s
    item["values"].fetch(value) do
      raise InvalidRules, "no categorical score for #{item['key']}=#{value}"
    end.to_i
  end

  def score_inspection_recency(item, evidence)
    last = evidence[:last_inspected_at]
    snapshot_at = evidence[:snapshot_at]

    bucket =
      if last.nil?
        "never"
      elsif last.to_date == snapshot_at.to_date
        "today"
      else
        "overdue"
      end

    item["values"].fetch(bucket).to_i
  end

  def reason_for(item, evidence, score)
    case item["type"]
    when "numeric_tier"
      value = evidence.fetch(item["field"].to_sym)
      "字段 #{item['field']}=#{value}，命中得分 #{score}/#{item['max']}"
    when "categorical"
      value = evidence.fetch(item["field"].to_sym)
      "字段 #{item['field']}=#{value}，命中得分 #{score}/#{item['max']}"
    when "inspection_recency"
      last = evidence[:last_inspected_at]
      if last.nil?
        "从未巡查，命中得分 #{score}/#{item['max']}"
      elsif last.to_date == evidence[:snapshot_at].to_date
        "当日已巡查，命中得分 #{score}/#{item['max']}"
      else
        "巡查时间为 #{last.iso8601}，较早，命中得分 #{score}/#{item['max']}"
      end
    end
  end

  def resolve_risk_level(total)
    level = @rules["risk_levels"].find do |band|
      total >= band["min"].to_i && (band["max"].nil? || total < band["max"].to_i)
    end
    raise InvalidRules, "no risk level matched for score #{total}" if level.nil?

    level["level"]
  end

  def build_explanation(breakdown, total, risk_level, dispatch_status, road_blocked)
    lines = breakdown.map do |entry|
      "#{entry[:name]}（#{entry[:key]}）= #{entry[:score]}/#{entry[:max]}：#{entry[:reason]}"
    end

    summary = +"总分 #{total}，风险等级 #{risk_level}，调度状态 #{dispatch_status}。"
    summary << "道路不可达，原始风险等级保留为 #{risk_level}，仅将调度标记为 blocked。" if road_blocked

    {
      "strategy_version" => strategy.version,
      "strategy_name" => strategy.name,
      "items" => lines,
      "sum_check" => breakdown.sum { |e| e[:score] },
      "total_score" => total,
      "summary" => summary
    }
  end
end
