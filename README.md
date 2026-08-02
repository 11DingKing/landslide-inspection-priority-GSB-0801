# 地灾巡查优先级服务 (Landslide Inspection Priority Service)

连续强降雨后，基层需要在大量隐患点中排出当天先巡哪里。本服务基于 **Ruby 3.4 / Rails 8.1 API 模式 / PostgreSQL** 构建，提供可解释的地灾巡查优先级评分、策略版本化、证据快照不可变、队列检索与重放能力。

## 核心设计原则

| 原则 | 实现方式 |
|------|----------|
| **评分规则与框架分离** | 所有评分数学逻辑集中在纯 Ruby 领域对象 `Scoring::Calculator`；控制器和 ActiveRecord 回调中**零评分规则** |
| **证据不可变** | `EvidenceSnapshot` 在 `lock!` 后无法修改；`PriorityScore` 行内冻结了分项名称、得分范围、快照时间和策略版本 |
| **策略可版本化** | `ScoringStrategy` 带 `version_code` / `effective_at` / `rules_json`；同一 `effective_at` 只能有一个已发布策略（数据库部分唯一索引强制） |
| **可重放** | 任何历史快照都可用任意策略版本重算，结果独立存储不覆盖；同一 (快照, 策略) 对幂等返回同一行 |
| **道路不可达不降级风险** | 封闭道路只将 `dispatch_status` 设为 `blocked`，`total_score` 和 `risk_level` 保持原值 |
| **分项之和严格等于总分** | 写入时校验、解释 API 再次校验；全整数运算，无浮点漂移 |
| **并发安全** | `(evidence_snapshot_id, scoring_strategy_id)` 唯一索引 + `find_or_create_by!`，多进程同时计算同一条快照只产生一行 |
| **分页稳定** | 排序键 `total_score DESC, hazard_point_id ASC`；相同分数按自增主键排，新写入的点位排在同分组末尾，页面不跳 |
| **确定性版本选择** | 策略选择规则：`published` + `effective_at <= as_of`，按 `effective_at DESC, published_at DESC NULLS LAST, id DESC` 取第一条 |

## 分项评分（v1.0 基线）

| 分项 | 范围 | 说明 |
|------|------|------|
| `rainfall_24h` | 0–40 | 24h 降水分档：≥150mm=40，≥100mm=30，≥50mm=18，≥0mm=5 |
| `historical_events` | 0–20 | 历史事件次数 × 8，上限 20 |
| `inspection_recency` | 0–20 | 从未巡查=20，>72h=15，24–72h=8，≤24h=0 |
| `point_type_weight` | 0–20 | 切坡建房=20，道路边坡=12，登记隐患=8 |
| **总分** | **0–100** | **分项直接相加** |

风险等级：≥75 critical，≥55 high，≥35 medium，其余 low。

## 三个种子点位

| 点位 | 类型 | 24h 降水 | 历史事件 | 上次巡查 | 道路 | 总分 | 风险 | 调度 |
|------|------|---------|---------|---------|------|------|------|------|
| 切坡建房点 A | cut_slope_building | 186mm | 2 | 从未 | 可达 | **96** | critical | available |
| 道路边坡点 B | road_slope | 112mm | 0 | 70h 前 | **封闭** | **50** | medium | **blocked** |
| 登记隐患点 C | registered_hazard | 95mm | 1 | 6h 前 | 可达 | **34** | low | available |

## 系统要求

- Ruby 3.4（已验证 3.4.10）
- Ruby on Rails 8.1（API 模式）
- PostgreSQL 14+（已验证 16/17）
- Bundler 2.x

## 安装

### 1. 安装依赖

```bash
bundle install
```

### 2. 配置数据库

默认连接 `localhost:5432`，使用系统用户名。可通过环境变量覆盖：

```bash
export DB_USERNAME=your_pg_user
export DB_PASSWORD=your_pg_password   # 如无密码可留空
```

如需创建 PostgreSQL 角色（以超级用户身份）：

```bash
psql -U postgres -d postgres -c "CREATE ROLE your_user WITH LOGIN SUPERUSER CREATEDB;"
```

### 3. 创建数据库、运行迁移、加载种子

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

种子会创建：基线策略 `v1.0-baseline` + 上方三个点位及其评分。

## 启动服务

```bash
bin/rails server
# 服务默认运行在 http://localhost:3000
```

健康检查：

```bash
curl http://localhost:3000/up
```

## 运行测试

```bash
# 全部快速测试（39 个 examples，约 1 秒）
bundle exec rspec --tag ~slow

# 包含万点排序压力测试（另加约 3–4 分钟）
bundle exec rspec
```

测试覆盖：
- 计算器纯函数、分项之和、范围锁定、风险等级
- 策略选择确定性、重叠发布拒绝（409 Conflict）
- 同快照并发计算（8 线程只产生 1 行）
- 旧快照用新策略重放
- 道路封闭不降级风险
- offset 和 cursor 分页、同分数排序稳定
- 10,000+ 点位排序 + 并发插入下首页不变
- 证据快照锁定后不可变
- API 端到端请求

## API 概览

完整规范见 [public/openapi.yaml](public/openapi.yaml)。

### 隐患点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/hazard_points` | 列表 |
| POST | `/hazard_points` | 创建 |
| GET | `/hazard_points/:id` | 详情 |
| PATCH | `/hazard_points/:id` | 更新 |

### 证据快照

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/hazard_points/:hazard_point_id/evidence_snapshots` | 列表 |
| POST | `/hazard_points/:hazard_point_id/evidence_snapshots` | 创建 |
| GET | `/hazard_points/:hazard_point_id/evidence_snapshots/:id` | 详情 |
| POST | `/hazard_points/:hazard_point_id/evidence_snapshots/:id/lock` | 锁定（不可变） |
| POST | `/hazard_points/:hazard_point_id/evidence_snapshots/:id/priority` | 计算优先级 |

### 策略版本

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/strategies` | 列表 |
| POST | `/strategies` | 创建草稿 |
| GET | `/strategies/:id` | 详情 |
| POST | `/strategies/:id/publish` | 发布（同生效时刻重复发布会 409） |
| POST | `/strategies/:id/retire` | 退役 |

### 优先级与队列

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/priority/queue` | 巡查队列（分页/筛选/游标） |
| GET | `/priority/:id/explain` | 解释评分（含分项和与版本） |
| POST | `/priority/replay` | 批量重放 |
| POST | `/priority/compute_latest` | 为所有最新快照批量计算 |

### 快速示例

```bash
# 查看队列
curl http://localhost:3000/priority/queue | jq

# 解释某个评分
curl http://localhost:3000/priority/1/explain | jq

# 为某个快照计算优先级（自动锁定快照）
curl -X POST http://localhost:3000/hazard_points/1/evidence_snapshots/1/priority

# 用特定策略版本重放
curl -X POST "http://localhost:3000/hazard_points/1/evidence_snapshots/1/priority?strategy_id=2"

# 游标分页
curl "http://localhost:3000/priority/queue?per_page=100&cursor=<next_cursor>"
```

## 代码结构

```
app/
├── controllers/
│   ├── application_controller.rb       # 错误处理
│   ├── hazard_points_controller.rb
│   ├── evidence_snapshots_controller.rb
│   ├── strategies_controller.rb
│   └── priorities_controller.rb        # 仅参数解析 + 调用领域服务
├── models/
│   ├── hazard_point.rb                 # 关联 + 验证（无评分规则）
│   ├── evidence_snapshot.rb            # 不可变保护（无评分规则）
│   ├── scoring_strategy.rb             # 版本模型 + 发布逻辑
│   ├── priority_score.rb               # 评分结果（无评分规则）
│   └── scoring/
│       ├── rules.rb                    # 规则参数值对象（冻结）
│       ├── calculator.rb               # ★ 纯函数评分器（唯一含数学逻辑的地方）
│       ├── strategy_selector.rb        # 确定性版本选择
│       ├── priority_computer.rb        # 应用服务：幂等持久化、重放、并发安全
│       └── queue_service.rb            # 队列检索、稳定排序、offset/cursor 分页
db/
└── migrate/
    ├── 20260802214327_create_hazard_points.rb
    ├── 20260802214328_create_evidence_snapshots.rb
    ├── 20260802214329_create_scoring_strategies.rb  # 含同生效时刻唯一索引
    └── 20260802214330_create_priority_scores.rb     # 含 (快照,策略) 唯一索引
spec/
├── models/scoring/
│   ├── calculator_spec.rb
│   ├── strategy_selector_spec.rb
│   ├── priority_computer_spec.rb       # 含并发与重放测试
│   └── queue_service_spec.rb           # 含 10,000 点位稳定排序测试
├── requests/priority_api_spec.rb
└── factories/factories.rb
public/
└── openapi.yaml                        # OpenAPI 3.1 规范
```

## 关键不变量

1. **分项和 = 总分**：`components.sum { |c| c["score"] } == total_score`，由 `PriorityComputer` 写入时验证，`/priority/:id/explain` 读取时再次验证。
2. **道路不可达只影响调度**：`road_accessible=false` 时 `dispatch_status="blocked"`，但 `total_score` 和 `risk_level` 与可达时完全相同。
3. **快照时间锁定**：`PriorityScore.snapshot_time` 在创建时从快照复制，后续快照变更不影响历史评分。
4. **策略唯一生效**：同一 `effective_at` 只能有一个 `published` 策略（PostgreSQL 部分唯一索引），第二个发布会返回 409。
5. **幂等并发**：同一 `(evidence_snapshot_id, scoring_strategy_id)` 始终返回同一行，无重复计算。
