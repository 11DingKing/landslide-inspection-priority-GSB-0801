# 地灾巡查优先级服务 (Landslide Inspection Priority)

Ruby 3.4 · Rails 8.1 (API 模式) · PostgreSQL

连续强降雨后，基层需要在大量隐患点中确定当天先巡哪里。本服务管理
**隐患点**、**不可变证据快照** 与 **版本化评分策略**，提供优先级计算、
队列检索和解释 API。

## 核心设计

| 关注点 | 机制 |
| --- | --- |
| 分项名称/得分范围锁定 | `Scoring::Engine::COMPONENTS`：`rainfall_24h` 0–40、`historical_events` 0–30、`inspection_recency` 0–30，总分固定 0–100；策略只能调阈值/权重，越界载荷在入库前被拒绝 |
| 分项之和 ≡ 总分 | 引擎用整数运算，总分就是分项的字面求和；`ScoreRecord` 模型校验再次断言 |
| 道路封闭 ≠ 风险消失 | `road_accessible=false` 只把 `scheduling_status` 置为 `blocked`，分数与 `risk_level` 原样保留 |
| 快照不可变 | `BEFORE UPDATE OR DELETE` 触发器 + 模型 `readonly?`；`captured_at` 创建即锁定 |
| 策略版本唯一解析 | 已发布版本的 `tstzrange` 生效区间由排他约束保证互不重叠；同一生效时刻的两个候选并发发布时恰有一个成功（另一个得到 409） |
| 历史重放 | 省略策略版本时按快照 `captured_at` 解析当时的版本重算；引擎为纯函数，重放结果与原判断逐字节一致；显式传版本号可做对比重放 |
| 并发计算幂等 | `(evidence_snapshot_id, strategy_version_id)` 唯一索引；并发计算同一快照只落一条记录 |
| 万级稳定分页 | 队列按 `(total_score DESC, id ASC)` 键集（keyset）分页，同分且持续写入时页序不来回跳；部分索引 `WHERE is_current` 支撑排序 |

评分规则全部集中在 `app/services/scoring/engine.rb`（纯 Ruby，无数据库、
无时钟副作用）；控制器与 ActiveRecord callback 中没有任何评分规则。

## 安装

```bash
# macOS (Homebrew)
brew install ruby@3.4 postgresql@16
export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"

# 启动 PostgreSQL（任一方式）
brew services start postgresql@16        # 需要 ~/Library/LaunchAgents 可写
# 或前台/手动：
# /opt/homebrew/opt/postgresql@16/bin/pg_ctl -D /opt/homebrew/var/postgresql@16 start

gem install rails -v '~> 8.0'
bundle install
```

## 初始化数据库与种子数据

```bash
bin/rails db:prepare   # 建库、跑迁移、载入种子
```

种子包含策略 v1 和三个点位（快照采集于种子执行时刻）：

| 点位 | 24h 降水 | 历史事件 | 最近巡查 | 道路 | 得分 | 等级 | 调度 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 切坡建房点 SLP-001 | 186mm | 2 | 空 | 可达 | 100 | high | schedulable |
| 道路边坡点 RDS-002 | 112mm | 0 | 较早（90 天前） | **封闭** | 55 | medium（保留） | **blocked** |
| 登记隐患点 REG-003 | 95mm | 1 | 当日 | 可达 | 35 | low | schedulable |

## 运行测试

```bash
bin/rails test
```

覆盖：引擎不变量（分项锁定、和=总分、不可达只阻塞）、快照不可变性
（模型层与触发器层）、策略重叠拒绝与同刻并发发布唯一胜出、同一快照
并发计算幂等、旧快照重放逐字节一致、对比重放、10,000 点位键集分页
在持续写入下的稳定性、API 端到端。

## 启动服务

```bash
bin/rails server   # http://localhost:3000
```

OpenAPI 文档见 [openapi/openapi.yaml](openapi/openapi.yaml)。

### 常用调用

```bash
# 巡查队列（第一页）
curl 'http://localhost:3000/api/v1/inspection_queue?limit=50'
# 翻页：带上上一页返回的 next_cursor
curl "http://localhost:3000/api/v1/inspection_queue?limit=50&cursor=$NEXT_CURSOR"

# 计算/重放某快照的优先级（省略策略版本 = 按快照时间解析当时的版本）
curl -X POST http://localhost:3000/api/v1/priorities \
  -H 'Content-Type: application/json' \
  -d '{"priority":{"evidence_snapshot_id":1}}'

# 对比重放：用 v2 规则重算旧快照
curl -X POST http://localhost:3000/api/v1/priorities \
  -H 'Content-Type: application/json' \
  -d '{"priority":{"evidence_snapshot_id":1,"strategy_version_id":2}}'

# 解释某条评分记录
curl http://localhost:3000/api/v1/priorities/1/explanation

# 发布新策略（先退役 v1 释放区间，否则与已发布区间重叠会得到 409）
curl -X POST http://localhost:3000/api/v1/strategy_versions/1/retire
curl -X POST http://localhost:3000/api/v1/strategy_versions \
  -H 'Content-Type: application/json' \
  -d '{
    "publish": true,
    "strategy_version": {
      "version": 2,
      "effective_from": "2026-09-01T00:00:00+08:00",
      "rules": {
        "rainfall_24h": {"thresholds": [{"gte_mm": 150, "score": 40}, {"gte_mm": 100, "score": 30}]},
        "historical_events": {"per_event": 15, "cap_events": 2},
        "inspection_recency": {"never": 30, "fresh": 0,
          "stale_days": [{"gte_days": 90, "score": 25}, {"gte_days": 30, "score": 15}, {"gte_days": 7, "score": 5}]},
        "risk_levels": [{"min_total": 70, "level": "high"}, {"min_total": 40, "level": "medium"}]
      }
    }
  }'
```

注意：种子策略 v1 的生效区间为 `[2026-01-01, ∞)`，在其退役前，任何
新策略的 `effective_from` 只要落入该区间都会被拒绝（409）。这是刻意
行为——已发布策略互不重叠，任意时刻只能解析出唯一版本。

## 目录速览

```
app/models/                 # HazardPoint / EvidenceSnapshot / StrategyVersion / ScoreRecord
app/services/scoring/       # 评分引擎（唯一包含评分规则的地方）
app/services/               # PriorityCalculator（幂等计算）、InspectionQueue（键集分页）
app/controllers/api/v1/     # 薄控制器：参数、调用服务、序列化
db/migrate/                 # 触发器、排他约束、唯一/部分索引
openapi/openapi.yaml        # OpenAPI 3.1 文档
test/                       # 引擎、模型、服务与集成测试
```
