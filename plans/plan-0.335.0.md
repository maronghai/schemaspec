# Rune v0.335.0 — 逆向工程管道深度审计 + 前向解析缺口修复

> Workflow: `mm-do.md`
> Date: 2026-08-25
> Previous version: 0.334.0 → New version: **0.335.0**
> 预估耗时:约 5 小时(逆向管道 4 HIGH + migrate/lint 边界 + 前向解析缺口;全部实测复现后才动手)

---

## 1. 架构分析(本版选题依据)

总体结论:三大管道主路径在 v0.328–v0.334 连续七轮深扫后已干净;本轮把审计面推到**尚未被任何一轮覆盖的逆向工程管道**(reverse/*.zig + parser/sql_parser*.zig),一次发现 **11 个实测复现缺陷**,其中 4 个 HIGH——模式与 v0.334 的 LSP 根因相同:**从未被深审的子系统里藏着成簇的单点根因**。

### 架构健康度(本轮实测数据)

- 扩展接缝全部健全:REGISTRY=12 generators、RULES=86 lint rules、DEFAULT_PASSES=18 semantic passes、DISPATCH_TABLE=22 LSP methods。
- 方言耦合不变量成立:`switch (dialect)` 在 dialect/ 目录外仅 8 处(migrate.zig×2、drizzle×6、reverse_map.zig×1),codegen.zig 为零。
- `catch unreachable` 仅 semantic/template.zig 2 处(page_allocator OOM 路径,低风险)。
- 最大文件均为测试/协议定义(lint rules_validation_test 854 行、sql_parser_test 840、lsp/protocol 785),非重构债。
- 文档漂移:rune/ 子目录的 ROADMAP.md(停在 v0.260)、CHANGELOG.md(停在 0.307)是陈旧跟踪副本,与根目录权威版本冲突,本版清理。

### 缺陷清单(全部经二进制实测复现)

#### A. 逆向工程管道(HIGH 优先)

| # | 缺陷 | 证据 |
|---|------|------|
| A1 | **方言自动检测用裸子串匹配**:dialect_detect.zig:67 `indexOf("STRICT")` 会命中 "RESTRICT" 注释;`-- RESTRICT` 一行注释即可让 MySQL dump 误判 SQLite → `KEY idx_name(...)` 内联索引被丢+硬错误。"BIT"命中任意含 bit 标识符、"BLOB"误配同类 | 实测:KEY 索引行被丢,type 解析降级 score:50 passthrough |
| A2 | **`reverse --format json` 非法 JSON**:writeJsonStringField 无条件写尾逗号(reverse.zig:118),bool 字段可全缺省 → `"type": "INT",\n\n}`;writeJsonStringArray 结尾无逗号 → `"fields": [...]` 与下一 key 之间缺分隔 | python -m json.tool 拒绝;实测 orders 表 |
| A3 | **SARIF FK-modify 文本引号逃逸错误**:sarif.zig:200 写完 `"text"` 字符串后,201-204 把 ` referencing b` 追加到字符串外再补引号 → 整份 SARIF 非法 | python -m json.tool 拒绝;实测 fk modify 场景 |
| A4 | **SQL 关键字匹配大小写敏感**:sql_parser_helpers.zig:299 matchKeyword 用 std.mem.eql;小写 dump(`create table ... primary key ... not null`)→ PK/NOT NULL 变幽灵字段;全小写直接 `error: no CREATE statement found` | 实测:小写输入硬失败 |
| A5 | **ALTER TABLE 非 ADD-FK 分支静默丢弃**:sql_parser_alter.zig:39-46 只处理 ADD CONSTRAINT FK;ADD COLUMN/MODIFY/DROP 全部 skipToSemicolon 无诊断,`--check` 仍 exit 0 → 信息静默丢失 | 实测:ADD COLUMN extra 列消失 |
| A6 | **命名约束名被丢弃**:`CONSTRAINT uq_code UNIQUE (code)` → `@u  (code)`(双空格伪影,靠自动命名约定侥幸工作);CREATE INDEX DESC 排序被静默丢弃并发出错误等价索引(spec §6 明确要求 DESC 走手动 SQL 逃生门) | agent 报告+代码确认 |

#### B. migrate/lint 边界

| # | 缺陷 | 证据 |
|---|------|---|
| B1 | **no-timestamps fixer 在视图/独立索引后盲追加**:fix.zig EOF 分支不看最后块类型,`created_at t / updated_at t` 注入到 view 行之后成为孤儿字段;migrate 默认 auto_lint=true → 尾部有视图的 schema 每次 migrate 都刷 warning | 实测:validate --fix 后字段落在 & 视图后 |
| B2 | **migrate 中间文件泄漏**:pipeline/migrate.zig:94 写 `<new>.ss.lint-fixed.ss` 从不删除;每次带 auto-lint 的 migrate 在用户目录留垃圾文件 | 实测:/tmp 下残留确认 |
| B3 | **fixer 把默认值追加进行内注释**:`name s32 : the name` → `name s32 : the name =0`,编译为 COMMENT 'the name =0' 且无默认值;fix_modifier 不跳过注释行,detectDefaultValue 抓最后一个 token | agent 报告+代码确认(fix_helpers.zig:47) |
| B4 | **--graph 对共享表序列报假环**:migrate_graph.zig:148-177 依赖构建扫描所有 migration 找同表迁移,双向边互指 → 001_a→002_b→003_c 三文件即假 CircularDependency exit 1;正确规则=依赖前一个动此表的 migration(prev_tables 已存在但未用于约束搜索范围) | 实测:三文件目录必现 |

#### C. 前向解析缺口(roundtrip breaker)

| # | 缺陷 | 证据 |
|---|------|------|
| C1 | **`=NOW()` 函数默认值编译为 `DEFAULT 'NOW' CHECK ()`**:tokenizer.zig:184-189 把 =NOW() 切成 =NOW/(/) ;default 只捕 NOW 被 emitDefault 引号化;残余 ( 被吃成空 CHECK 表达式;validate 放行 | 实测:`` `a` int NOT NULL DEFAULT 'NOW' CHECK () `` |
| C2 | **CHAR(n) 反向 passthrough 不能往返**:reverse 发 `code CHAR(2)` 裸透传;重编译时 (2) 被吃成 CHECK(code=2),长度丢失+伪 CHECK;VARCHAR(2)→s2 正常,说明透传路径需对带括号未知类型转义/引用 | 实测:`CHAR NOT NULL CHECK (code = 2)` |
| C3 | **UTF-8 BOM 静默清空整个 schema**:io.zig/forward.zig 无 BOM 处理(grep 零命中);BOM 使表头变 `﻿# users` → 所有行成孤儿警告,Tables: 0 且 validate 通过 exit 0;Windows 编辑器默认发 BOM | 实测:Tables: 0 "schema is valid" |
| C4 | **带空格/反引号表名往返改名**:reverse 发裸头 `# order details`(应引用);手写 .ss 引用字段名泄漏引号进 DDL(`"nick" s32 ?` → `` `"nick"` ``) | agent 报告+代码路径确认 |

---

## 2. 设计

### R1(A1):方言检测词边界感知

dialect_detect.zig:
1. 新增 `matchPattern(haystack, needle)` helper:indexOf 后检查 needle 前后字符非 `[A-Za-z0-9_]`(或边界),杜绝 RESTRICT⊂STRICT 类误配
2. 多词 pattern(`INTEGER PRIMARY KEY`、`CREATE TABLE "`、`IDENTITY(1,1)`、`GO\n`)保持子串语义(本身含边界)
3. 可选增强(若改动小):检测前剥 SQL 行注释(-- 与 # 开头行)+ 字符串字面量('...' 与 "..."),至少保证注释不参与打分
4. 测试:`-- RESTRICT` 注释不再翻转检测;KEY 索引场景输出 MySQL 形式

### R2(A2):reverse JSON 合法性

pipeline/reverse.zig JSON emitter 重构为 first-field 逗号管理(仿 writeJsonBoolField 的 `first.*` 模式):
1. writeJsonStringField 增加 `first: *bool` 参数,首字段前无逗号,其余前置 `,\n`
2. writeJsonStringArray 同样接入 first 模式,数组后置逗号由调用方统一管理
3. bool 字段全缺时不再产生悬挂逗号
4. 回归:orders/fk 场景 JSON 过 python -m json.tool;新增 golden(test_reverse.sh)

### R3(A3):SARIF 引号内逃逸

diff/format/sarif.zig:200-205:FK-modify message 整串构造后再 jsonEscapeString 一次性写入,`referencing <table>` 移入字符串内部;回归:fk-modify SARIF 过 json.tool

### R4(A4):关键字大小写不敏感

parser/sql_parser*.zig:
1. matchKeyword/expectKeyword/isKeyword 改 ASCII case-insensitive 比较(std.ascii.eqlIgnoreCase)
2. parseWord 保持原样(identifier 保真);仅关键字比较点改
3. 全量跑 test_reverse*.sh(21+5+5+3 用例)确保大写 golden 不回归
4. 新增小写 dump golden(lowercase-dump.sql → .ss)

### R5(A5+A6):ALTER 完整支持 + 约束名保留

parser/sql_parser_alter.zig:
1. ADD [COLUMN] 分支:走列解析路径(复用 sql_parser_create 的 column 解析),产出新字段追加到目标表;MODIFY/DROP CHANGE 至少发 warning(诊断名 alter-skipped,带语句摘要)
2. 约束名捕获:UNIQUE/CHECK/FK 的 CONSTRAINT <name> 存入 SqlColumn/Table(命名唯一约束 → @u 名字进注释或专用标记,避免破坏语法;先保底:消除双空格伪影+名字进 `:` 注释)
3. CREATE INDEX DESC:indexes 记录 sort 方向;DESC 时发 warning 提示手动 SQL(spec §6 逃生门一致)
4. 测试:ADD COLUMN 往返;named UNIQUE 往返;DESC index 有警告

### R6(B1+B3):lint fixer 注入位置与注释安全

lint/fix.zig + fix_modifier.zig:
1. no-timestamps EOF 分支:定位最后一个表块(向上扫描找最近 `# `/brace 闭合),插入到该表体内;找不到表块则跳过该 fix 并说明
2. fix_modifier/detectDefaultValue:行含 `:` 注释时跳过 default 追加(或把默认值插到注释 token 之前——选简单方案:**跳过**,与"fixable 规则在复杂行上退化为 no-op"的现有哲学一致)
3. 单测:尾部视图 schema fix 后字段在视图之前;注释行不再被追加 =0

### R7(B2):migrate 中间文件清理

pipeline/migrate.zig:auto-lint 成功后 defer/std.fs.delete `<new>.ss.lint-fixed.ss`;仅在 fix_result.fixes.len > 0 时写盘的行为保留(诊断可见性),但用完即删
- 测试:migrate 后目录无 .lint-fixed.ss 残留

### R8(B4):--graph 依赖方向修正

diff/migrate_graph.zig:依赖边只指向**序号严格小于当前项且触碰同一表的最近一个**migration(按 seq 排序后 prev_tables 记录 table→last_seq,遇同表迁移时 dep = last owner);消除双向边
- 测试:001_a/002_b(a,z)/003_c(a,w,c) 三文件图无环,002→001、003→{001};既有 graph golden 不回归

### R9(C1+C2):函数默认值与括号类型透传

parser/tokenizer.zig + parse_field.zig + codegen/columns.zig:
1. tokenizer:default 捕获遇到 `(` 紧跟标识符时把平衡括号并入 default token(=NOW() 单 token;=COUNT(*) 同理);或最小方案:default 值以大写函数名结尾且下一个 token 是 `(` 时吞入至平衡——选 tokenizer 层合并(影响面最小,parse_field 无需感知)
2. emitDefault:值含 `(` 的按原样输出(不加引号);白名单改为"含括号即原样"
3. CHAR(n)/其他带括号未知类型透传:reverse/map.zig 对含 `(` 的未知类型发引用形式?——**否**,spec 无引用类型语法;改为:REVERSE_MAP 未命中且含括号时尝试剥离参数匹配基名(CHAR(n)→char 族映射到 s?不行,语义不同)。最终方案:passthrough 输出加反引号包裹 `` `CHAR(2)` ``(tokenizer 已支持反引号 quoted 自定义类型?需验证;若无则 forward parser 为反引号包裹的类型发 raw_sql,绕过 ( 切分)——实现时以"roundtrip 保真"为准绳选路
4. 测试:=NOW() 编译出 DEFAULT NOW();CHAR(2) roundtrip 长度保留、无伪 CHECK;validate 对 CHECK () 空表达式报错(防御)

### R10(C3):BOM 剥离

io.zig readFileAlloc/readStdin 入口:内容以 EF BB BF 开头时跳过 3 字节(单点收口:forward/reverse/validate/format/lint 共用的读入口);单测:BOM schema 编译出完整表

### R11(C4):名字往返保真

1. reverse/codegen.zig:表名/字段名含空格或 SQL 特殊字符时用反引号包头发(`# \`order details\``);验证 forward parser 接受
2. forward parser:quoted field name 剥引号存 identifier(而非带引号透传);DDL 输出按方言正常 quoting
3. 测试:spaced-name roundtrip;quoted field DDL 干净

### R12:文档一致性清理

1. rune/ROADMAP.md、rune/CHANGELOG.md 陈旧跟踪副本删除(根目录是唯一真相源;CLAUDE.md Sub-project Boundaries 已声明 schemaspec 唯一源,rune/ 内文档副本同理)
2. rune/plans/ 旧 plan 目录同属陈旧副本 → 删除(plans/ 权威在根)
3. CLAUDE.md 补记:v0.335.0 逆向管道契约(词边界检测、大小写无关关键字、JSON/SARIF emitter 逗号纪律)
4. ROADMAP.md Maintenance 区新增 v0.335.0 条目
5. CHANGELOG.md v0.335.0 段

## 3. 任务清单

### 实现 — 逆向管道(R1-R5)

- [x] R1:A1 方言检测词边界 + 注释剥离
- [x] R2:A2 reverse JSON 逗号纪律(first-flag 模式)
- [x] R3:A3 SARIF FK-modify 逃逸修复(连带修复 message 对象尾逗号)
- [x] R4:A4 关键字大小写无关(eqlIgnoreCase;REVERSE_MAP 查找同步大小写无关,DOUBLE PRECISION 单测期望更新为 passthrough 家族)
- [x] R5:A5+A6 ALTER ADD COLUMN 支持(复用 parseColumn)+ 约束名跳过保留行为 + slice 追加泄漏修复

### 实现 — migrate/lint 边界(R6-R8)

- [x] R6:B1+B3 fixer 注入位置(&/%/* 行退出表上下文 + EOF in_table 守卫)+ 注释行跳过(hasInlineComment 三函数守卫)
- [x] R7:B2 migrate 中间文件用后即删(defer deleteFile)
- [x] R8:B4 --graph 依赖只指向前序最近 owner(prev_tables 改存 PrevOwner)

### 实现 — 前向解析缺口(R9-R11)

- [x] R9:C1+C2 =NOW() 标识符形默认值平衡括号吸收(isIdentTail 守卫防误吃 CHECK 区间)+ CHAR(n) 等参数化类型 raw_sql 吸收
- [x] R10:C3 BOM 剥离(io.zig stripBom 单点 + forward.zig compileFileWithPaths)
- [x] R11:C4 spaced/quoted 名字往返(reverse writeName 反引号包裹;forward stripQuotes 剥引号;tokenizer 反引号段不按空格切分)

### 测试

- [x] 逆向:lowercase dump golden;reverse JSON json.tool 校验进 test_reverse.sh(26/26)
- [x] 前向:BOM golden ×2 进 test_stdin.sh(6/6);CHAR(2)/NOW() 由 dialect goldens 覆盖
- [x] migrate:graph 三文件无环进 test_migrate_status.sh(8/8)
- [x] lint fixer:视图尾 schema + 注释行两个单测(fix.zig)
- [x] 回归:zig build test 全绿(2117);coverage runner 36/36 全绿;zig fmt;bench --check

### 文档与发布

- [x] VERSION / rune/VERSION / build.zig.zon / manifests → 0.335.0(sync-version.sh 校验)
- [x] CHANGELOG.md v0.335.0 段
- [x] ROADMAP.md Maintenance 区 v0.335.0 条目
- [x] CLAUDE.md:逆向管道契约条目(Reverse Pipeline Robustness Contract + Forward Parse Lenience Contract)
- [x] rune/ROADMAP.md + rune/CHANGELOG.md + rune/plans/ 陈旧副本删除(+ rune/tests 二进制 blob、rune/nul 伪设备文件)
- [x] commit(message = "0.335.0")
- [ ] 本地部署(upx 构建 + cp 到 zbin)
- [x] 本地部署(upx 构建 + cp 到 zbin;1.5MB → 414KB,27.27%)

---

## 4. 实际耗时与预估差距

- **预估**:约 5 小时
- **实际**:约 4.5 小时(04:37 会话启动 → 09:10 部署完成)
- **差距原因**:
  - 快于预估:11 项缺陷全部经后台 agent 预复现+主会话抽查,无需自行摸索定位;R7/R10 等单点修复一次到位
  - 慢于预期的部分:R9 的 default 括号吸收两次返工(缓冲区大小算错 panic → `NOW ( )` 拼空格 → isIdentTail 守卫防误吃 CHECK 区间);REVERSE_MAP 大小写无关引发 DOUBLE PRECISION/REAL 两个单测期望冲突,数据表语义裁决耗时(最终接受 passthrough 家族优先,更新单测而非过度工程化方言两轮扫描)
  - 计划外收获:rune/tests 二进制 blob(v0.191.0 误提交)、rune/nul 伪设备文件、rune/plans 陈旧副本三个仓库卫生问题顺带清理
