# 地灾巡查优先级服务

基于 Ruby 3.4 + Rails 8 API + PostgreSQL 的可解释地灾巡查优先级服务。连续强降雨后，对大量隐患点按风险排序，生成当日巡查队列，并对每一条结果给出分项得分、规则版本和文字解释。

## 核心设计

| 需求 | 实现 |
| --- | --- |
| 评分规则可版本化、可重放 | `ScoringStrategy` 保存完整规则 JSON（分项名称、得分范围、阈值），`ScoringEngine` 纯 Ruby 读取规则计算；`PriorityCalculator.replay` 用任意历史策略版本对旧快照重新评分。v1 发布后不 retired，旧快照持续绑定 v1 并可重放 |
| 分项之和严格等于总分 | `ScoringEngine` 直接以分项求和得到总分；`EvidenceSnapshot` 模型校验 `score_breakdown.sum == total_score` |
| 策略同一生效时刻唯一 | 已发布策略在 `effective_at` 上有唯一部分索引；并发发布第二个候选返回 409（`StrategyManager::OverlappingStrategy`） |
| 解析时刻唯一生效版本 | `StrategyResolver.resolve(time)`：`effective_at <= time ORDER BY effective_at DESC, version DESC LIMIT 1` |
| 道路不可达不降为 0 | 原始 `total_score`/`risk_level` 原样保留，仅把 `dispatch_status` 标为 `blocked` |
| 不可变证据快照 | `evidence_snapshots` 表上有 PG 触发器，禁止 `UPDATE`/`DELETE`；写入时冻结原始证据与计算结果 |
| 业务标识幂等/冲突 | `business_id` 唯一索引；同标识同载荷返回已有快照（200），同标识异载荷返回 409；并发提交只留下一条 current 快照 |
| 控制器/callback 不含评分规则 | 所有评分逻辑在 `app/services/scoring_engine.rb`；模型只有数据校验，控制器只做参数与调用 |
| 锁定分项名称、得分范围、快照时间 | 分项 `key/name/max` 与 `snapshot_at` 一并写入不可变快照；规则随策略版本固化 |
| 一万点排序 + 稳定分页 | 游标分页 `ORDER BY total_score DESC, id ASC`，索引 `(dispatch_status, total_score, id)`；同得分以 `id` 为稳定次序，持续写入不跳页 |

## 技术栈

- Ruby 3.4
- Rails 8.1（API 模式）
- PostgreSQL（使用 JSONB、`DISTINCT ON`、部分索引、触发器）
- RSpec + FactoryBot

## 目录结构

```
app/
  controllers/api/v1/    # 隐患点、优先级、队列、策略、快照 API
  models/                # HazardPoint / EvidenceSnapshot / ScoringStrategy
  serializers/           # 纯 Ruby 序列化器
  services/
    scoring_engine.rb        # 唯一的评分规则所在
    strategy_resolver.rb     # 时刻 -> 唯一策略版本
    strategy_manager.rb      # 发布草稿、冲突拒绝
    priority_calculator.rb   # 生成/重放快照
    queue_retriever.rb       # 稳定游标分页
lib/
  scoring_rules.rb       # v1 默认规则定义
db/migrate/              # 三张表 + 不可变触发器
spec/                    # 61 个自动化测试
public/openapi.yaml      # OpenAPI 3.0 文档
```

## 分项与评分（v1，满分 100）

| key | 名称 | 满分 | 规则 |
| --- | --- | --- | --- |
| `rainfall_24h` | 24小时降水 | 40 | [0,50)→0，[50,100)→10，[100,150)→25，[150,200)→35，≥200→40 |
| `historical_events` | 历史事件次数 | 25 | 0→0，1→12，≥2→25 |
| `point_type_risk` | 点位类型基础风险 | 20 | 切坡建房 20 / 道路边坡 12 / 登记隐患 8 |
| `inspection_recency` | 巡查时效 | 15 | 从未巡查 15 / 当日已巡查 0 / 较早 15 |

风险等级：`[0,30) low`、`[30,60) medium`、`[60,80) high`、`[80,100] critical`。

调度状态：道路可达为 `schedulable`，道路封闭为 `blocked`（不影响分数与风险等级）。

## 策略版本窗口

| 版本 | 生效时刻 | 说明 |
| --- | --- | --- |
| v1 | `2026-01-01T00:00:00Z` | 覆盖 `[2026-01-01, 2026-08-02)`；发布后不 retired，旧快照持续绑定并可重放 |
| v2 | `2026-08-02T00:00:00Z` | 自边界时刻起生效 |

边界时刻 `2026-08-02T00:00:00Z` 及之后解析到 v2，之前解析到 v1。

## 内置种子点位

| 点位 | 类型 | 24h 降水 | 历史事件 | 道路 | 最近巡查 | 快照时刻 | 绑定版本 | 分数 | 风险 | 调度 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 切坡建房点 A | cut_slope_building | 186mm | 2 | 可达 | 空（从未） | 2026-08-01T12:00Z | v1 | 95 | critical | schedulable |
| 道路边坡点 B | road_slope | 112mm | 0 | 封闭 | 较早 | 2026-08-01T12:00Z | v1 | 52 | medium | blocked |
| 登记隐患点 C | registered_hazard | 95mm | 1 | 可达 | 当日（同快照日） | 2026-08-01T12:00Z | v1 | 30 | medium | schedulable |
| RDS-002 | road_slope | 210mm | 0 | 封闭 | 空（从未） | 2026-08-02T00:00Z（边界） | v2 | 67 | high | blocked |

RDS-002 快照业务标识为 `evidence-rds-002-20260802-0000`；道路封闭仅使调度状态为 `blocked`，风险等级仍为 `high`。

## 业务标识与幂等

计算优先级时传 `business_id`：

* 相同 `business_id` + 相同证据载荷 → 返回已有快照，HTTP 200（幂等）。
* 相同 `business_id` + 不同证据载荷 → HTTP 409（冲突）。
* 并发提交相同 `business_id` → 数据库唯一索引保证只留下一条 current 快照，其余返回同一条。
* 比对的载荷包含：降水量、历史事件次数、点位类型、道路状态、最近巡查时间、快照时刻、策略版本。

## 安装

```bash
# 1. 安装依赖（需要 Ruby 3.4、Bundler、PostgreSQL）
bundle install

# 2. 创建数据库、执行迁移、写入种子数据
bin/rails db:prepare
# 等价于 db:create db:migrate db:seed
```

数据库连接默认走 `localhost:5432`，可用环境变量覆盖：
`DB_HOST`、`DB_PORT`、`DB_USERNAME`、`DB_PASSWORD`。

## 启动

```bash
bin/rails server
# 默认 http://127.0.0.1:3000
```

健康检查：`GET /up`

## 测试

```bash
# 准备测试库（首次）
RAILS_ENV=test bin/rails db:create db:migrate

# 运行全部测试
bundle exec rspec
```

测试覆盖：

- 评分引擎各分项与风险等级、分项和=总分、确定性
- 道路不可达保留原始风险、仅标记 blocked
- 策略版本解析（含时刻回退、忽略草稿）
- 同一生效时刻并发发布被唯一索引拒绝（多线程）
- 同一证据快照并发计算结果一致（多线程）
- 历史快照用新版本重放、原快照不变
- 快照不可变（DB 触发器阻止 UPDATE/DELETE）
- 一万个点位排序、游标分页无重复无遗漏、5 秒内完成
- 持续写入相同得分行时游标分页顺序稳定、不跳页
- v1/v2 边界时刻版本解析与快照绑定
- 业务标识幂等：同载荷 200、异载荷 409、并发只留一条
- API 请求规格（计算、队列、解释、发布冲突、重放）

## 常用 API

> 完整定义见 [public/openapi.yaml](public/openapi.yaml)。

### 计算优先级

```bash
curl -X POST http://127.0.0.1:3000/api/v1/hazard_points/4/calculate_priority \
  -H 'Content-Type: application/json' \
  -d '{"at":"2026-08-02T00:00:00Z","rainfall_24h_mm":210.0,"business_id":"evidence-rds-002-20260802-0000"}'
```

返回带 `scoring.score_breakdown`、`scoring.strategy_version`、`explanation` 的不可变快照。可用 JSON body 传 `at`、`strategy_version`、`rainfall_24h_mm`、`business_id`。提供 `business_id` 时：同载荷重复提交返回 200，不同载荷返回 409。

### 巡查队列

```bash
curl 'http://127.0.0.1:3000/api/v1/queue?limit=50'
# 下一页用 meta.next_cursor
curl 'http://127.0.0.1:3000/api/v1/queue?limit=50&cursor=...'
# 仅可调度点
curl 'http://127.0.0.1:3000/api/v1/queue?include_blocked=false'
```

### 解释

```bash
curl http://127.0.0.1:3000/api/v1/hazard_points/1/priority_explanation
```

### 发布策略

```bash
# 创建草稿
curl -X POST http://127.0.0.1:3000/api/v1/strategies \
  -H 'Content-Type: application/json' \
  -d '{"strategy":{"name":"v2","effective_at":"2026-08-02T00:00:00Z","rules":{...}}}'

# 发布（同 effective_at 已存在发布策略时返回 409）
curl -X POST http://127.0.0.1:3000/api/v1/strategies/2/publish
```

### 重放历史快照

```bash
curl -X POST http://127.0.0.1:3000/api/v1/snapshots/1/replay \
  -H 'Content-Type: application/json' \
  -d '{"strategy_version":2}'
```

## 数据模型要点

- `hazard_points`：隐患点静态属性（类型、历史事件次数、最近巡查时间、道路状态、最新降水）。
- `scoring_strategies`：版本号、生效时刻、状态（draft/published）、完整规则 JSON；已发布后规则不可改。
- `evidence_snapshots`：每次计算生成一行不可变记录，包含证据原值、策略版本、总分、分项、风险等级、调度状态与解释。
