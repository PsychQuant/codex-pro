## Context

codex-pro 已 stable 為 marketplace 殼 + 同名 single plugin、含 setup 與 batch 兩個 skill，但 4 個 archive cycle 後仍無 automated test。所有 verify 集中在 apply phase 的 inline Bash simulation — 跑完即散、無 persistence、無 regression net。

本 change 引入 test 場景，把 simulation 從 inline 轉為 standalone runnable scripts。目標：用 minimal-dependency Bash 寫出三層 test（static / behavioral / manual checklist），既能驗 artifact 結構正確、也能驗 skill 行為符合 spec scenarios。

## Goals / Non-Goals

**Goals:**

- Layer 1 static.sh：對所有 manifest（marketplace.json、plugin.json）跑 JSON schema parse；對所有 SKILL.md 跑 frontmatter parse；對 batch template 跑 `bash -n` 與 known-good sha256 比對；跑 namespace consistency grep
- Layer 2 setup.sh：把現有 setup 三 check 在 isolated env（fake HOME / PATH 剝離 / mktemp fake plugin root）重跑、assert 預期 status code 與 output
- Layer 2 batch.sh：驗 SKILL.md exception 標記、template 內 codex exec invocation 結構、parallel orchestration markers（`&` + `wait`）
- Layer 3 e2e-checklist.md：手動 e2e 確認步驟，不自動化
- `tests/run.sh` dispatcher：跑 Layer 1+2 報 pass/fail count、exit code 反映結果
- 共用 helper `tests/lib/assert.sh` + `tests/lib/isolate.sh` 集中 assertion 與 isolation 模式
- CLAUDE.md 與 README.md 反映新 capability

**Non-Goals:**

- 不引入 bats / pytest / shellcheck（外部依賴）
- 不寫 GitHub Actions / CI（local dev only）
- 不自動化 Claude Code TUI e2e（自動化 expect/agent-browser 對 TUI 行為脆弱、ROI 低）
- 不修改 setup 或 batch SKILL.md 本身（純 read-only 觀察其行為）
- 不變更 spec setup 或 spec batch 的任何 requirement
- 不加 namespace 為 codex-pro 以外的 test target（只測本 plugin）

## Decisions

### D1: Layout 採 tests/ at root + per-layer entry script

```
codex-pro/
└── tests/
    ├── run.sh                 ← dispatcher
    ├── static.sh              ← Layer 1
    ├── setup.sh               ← Layer 2 (setup skill)
    ├── batch.sh               ← Layer 2 (batch skill)
    ├── e2e-checklist.md       ← Layer 3 (manual)
    └── lib/
        ├── assert.sh
        └── isolate.sh
```

理由：

- single-plugin marketplace 結構下，per-layer 比 per-skill 自然 — Layer 1 跨 skill 共用、Layer 2 才分 setup/batch
- run.sh 為 single entry point、user 跑一條命令即驗全部
- lib/ 集中 shared helper，避免重複定義 assert 函數

Alternatives:

- per-skill nested（plugins/codex-pro/skills/setup/tests/）：skill 拆 plugin 出去時 test 跟著，但本專案 D2 of consolidate-naming 已決定 single-plugin within marketplace、不會拆，這套 layout 無實用價值
- 用 `__tests__` 慣例：偏 Node.js 文化、與本專案 Bash 風格不一致

### D2: Runner 採 pure Bash + small helper lib

無外部 framework（bats / pytest / shellcheck）。`lib/assert.sh` 提供 8 個 helper 函數：

| 函數 | 功能 |
|---|---|
| `assert_eq "$expected" "$actual" "$msg"` | 兩值相等 |
| `assert_contains "$haystack" "$needle" "$msg"` | substring check |
| `assert_file "$path" "$msg"` | 檔案存在且可讀 |
| `assert_no_file "$path" "$msg"` | 檔案不存在 |
| `assert_sha256 "$path" "$expected_hex" "$msg"` | shasum 與 hex 一致 |
| `assert_exit "$expected_code" "$cmd..." "$msg"` | 命令 exit code 比對 |
| `fail "$msg"` | 標記失敗、increment FAIL_COUNT |
| `pass "$msg"` | 標記成功、increment PASS_COUNT |

`lib/isolate.sh` 提供 3 個 wrapper：

- `with_empty_home <cmd>` — `HOME=/nonexistent` sub-shell 跑 cmd
- `with_path_stripped <cmd>` — `PATH=/usr/bin:/bin` sub-shell 跑 cmd（剝離 plugin bin/）
- `with_fake_plugin_root <body>` — `mktemp -d` 建立 fake plugin root、export `CLAUDE_PLUGIN_ROOT`、跑 body、cleanup

理由：

- 整個 plugin 是 shell + JSON + markdown、無 Node / Python runtime 約定
- bats 雖 lightweight 但仍需 `brew install bats-core` 多一層 user setup
- 自家 helper lib < 100 行、function naming 一致、debug 容易

Alternatives:

- bats-core：換 `@test` block syntax 與 better test reporting；代價：安裝步驟、SKILL 不再「跑 bash tests/run.sh 即可」
- inline assertion（每個 layer 各寫自家 assert）：重複定義、未來修 assert 行為要改多處

### D3: Isolation 策略採 sub-shell 變數 override

| Test 情境 | Isolation 機制 |
|---|---|
| OAuth token missing | `with_empty_home` → `HOME=/nonexistent` |
| codex-call PATH 缺失 | `with_path_stripped` → `PATH=/usr/bin:/bin` |
| Plugin manifest 壞 | `with_fake_plugin_root` → mktemp + 寫壞 JSON |
| `~/.codex/` read-only verify | `ls -la ~/.codex/` 前後 diff（不需 isolation、純 verification） |

理由：

- 之前 apply phase simulation 已驗證 `HOME=/nonexistent` 對 setup Check 1 work、`CLAUDE_PLUGIN_ROOT` 對 manifest self-check work — 沿用相同模式
- sub-shell 變數 override 是 POSIX、無 platform 依賴、cleanup 自動（sub-shell 結束變數消失）

Alternatives:

- docker 容器 isolation：100% sealed 但 user macOS dev、docker 啟動成本高、test 慢
- mock filesystem：no Go library to wrap shell；自寫 mock 框架重

### D4: Layer scope split

| Layer | 內容 | 自動化 |
|---|---|---|
| Layer 1 static | manifest schema、frontmatter parse、`bash -n`、namespace grep、template sha256 | 全自動 |
| Layer 2 behavioral | setup 三 check isolated 重跑、batch template 結構 grep | 全自動 |
| Layer 3 manual | claude --plugin-dir + skill 觸發 + 輸出 markdown 比對 | 手動 checklist |

理由 Layer 3 manual：

- Claude Code TUI 自動化（expect / agent-browser）對非 web TUI 介面脆弱
- e2e 行為 1-2 次驗證即知是否破壞、不像 unit test 需 regression run
- Manual checklist 形式（markdown checkboxes）讓 user 跑時逐項打勾即可、零 setup

Alternatives:

- Layer 3 也自動化：用 expect 模擬 TUI 輸入；ROI 低、TUI 版本飄移時 brittle
- Layer 3 不寫任何文件：失去 manual verify 的 checklist 結構、user 容易漏項

### D5: Known-good invariants 編碼為 assertion

Test 內 hardcode 以下 invariants：

- batch template sha256: `746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0`（從 add-batch-skill task 1.2 紀錄）
- Namespace prefix: `/codex-pro:`（從 consolidate-naming 鎖定）
- Marketplace name: `codex-pro`
- Plugin name: `codex-pro`（同 marketplace 名）
- 不允許出現的舊 namespace: `/codex-pro-setup`、`codex-pro-setup` plugin 名

理由：

- sha256 鎖住 batch template byte-identical — 未來若有人不小心改 template、test 立即 fail；若 deliberate 升級、同步改 hardcoded sha
- Namespace assertions 編碼「絕不再回到 marketplace-pivot 的 `/codex-pro-setup:` 命名」紀律
- Marketplace / plugin 同名是 consolidate-naming 的核心 invariant

Alternatives:

- 不 hardcode sha、跑 test 時動態算：失去 byte-identical 紀律的 enforcement、template 漂移無告警
- Namespace 用 config file 讀取：增加 indirection、test 自身要 parse config

## Implementation Contract

#### Behavior

User 在 codex-pro repo root 跑 `bash tests/run.sh`，跑全部 Layer 1+2、回報 pass/fail count、exit code 0 表全 pass。Layer 3 為 `tests/e2e-checklist.md` 手動文件，user 自行打勾。

跑單一 layer 可：`bash tests/static.sh`、`bash tests/setup.sh`、`bash tests/batch.sh`。

#### Interface

- Entry: `tests/run.sh`
- Layer scripts: `tests/{static,setup,batch}.sh`
- Manual checklist: `tests/e2e-checklist.md`
- Helper lib: `tests/lib/{assert,isolate}.sh`
- 命令列引數: 各 layer script 接受可選 `-v` (verbose)，否則只報 fail
- 副作用: 跑 test 期間建立 mktemp dir、跑完 cleanup；不寫入 codex-pro 內任何 artifact；不改 `~/.codex/`

#### Test invariants enforced

- `assert_sha256` 對 `plugins/codex-pro/skills/batch/references/script-template.sh` 比對 `746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0`
- grep `/codex-pro-setup` 整個 codex-pro 出現次數 = 0
- grep `/codex-pro:` 出現 ≥ 5 次（at least setup + batch 命名）
- marketplace.json plugins[0].name == plugin.json name == `codex-pro`
- SKILL.md frontmatter `name` 與 dir basename 一致（setup→setup、batch→batch）

#### Failure modes

- Helper lib 缺失 → run.sh 第一行 source 失敗、立即 abort
- python3 缺失（系統依賴）→ static.sh JSON parse fail；對 macOS 預期常駐
- mktemp 失敗 → with_fake_plugin_root 報告錯誤、test 跳過該項
- Concurrent test 跑 → mktemp dir 各自獨立、無 race（但本專案 default sequential）

#### Acceptance criteria

- `bash tests/run.sh` 在乾淨 codex-pro repo 跑、全 pass、exit 0
- `bash tests/static.sh` 對當前 codex-pro 結構全 pass
- `bash tests/setup.sh` 跑 setup 三 check 在 isolated env 各 scenario 對應 status、read-only verify pass
- `bash tests/batch.sh` template sha256 與 hardcoded 一致、exception 標記存在、parallel orchestration markers 全存在
- `tests/e2e-checklist.md` 內含至少 6 個 manual check 條目（setup ready、setup missing OAuth、batch trigger、batch 5 params 詢問等）
- 故意改壞 marketplace.json 後 static.sh 對應 assertion fail（demo 驗證 fail path）

#### Scope boundaries

In scope:

- 7 個新檔案於 tests/
- CLAUDE.md / README.md 加 Tests 段
- 新 capability tests 的 spec（含 scenarios for static / behavioral / manual）

Out of scope:

- bats / pytest / shellcheck 引入
- GitHub Actions / CI
- Claude Code TUI e2e 自動化
- 任何 setup / batch SKILL.md 或 spec 的 requirement 修改
- 跨 plugin test（其他 codex-pro skill 未來才有、本 change 不預留）

## Risks / Trade-offs

- [Hardcoded sha256 升級時要手動同步] → 若 batch template 後續正當升級（如 codex CLI 新 flag），test 會 fail。Mitigation: 升級該 template 必須在同一 change 內同步改 hardcoded sha + 加 commit message 標註「template sha bumped」。
- [Layer 3 manual 無 enforcement] → user 跑 manual checklist 可能漏項。Mitigation: e2e-checklist.md 用 markdown `- [ ]` 形式、明列每項；CLAUDE.md 寫「重大 namespace / spec change 之後跑 Layer 3」紀律。
- [Helper lib bug 散播] → 若 assert_eq 寫錯，所有 test 都受影響。Mitigation: lib/assert.sh < 50 行、function 各自獨立、test scripts 內每個 assertion 都附 msg 方便定位、首次跑 layer 1+2 後 user 必須手動 sanity check 一次。
- [python3 macOS 版本飄移] → static.sh 依賴 python3 parse JSON、若用戶系統 python3 stub（macOS 預設）會失敗。Mitigation: 在 run.sh 開頭 `command -v python3` check、fail fast with 「請裝 Xcode Command Line Tools」訊息。
