# Tested games / 实测游戏记录

[English README](../README.md) · [中文 README](../README.zh-CN.md) · [排障](troubleshooting.md)

**记录核对日期：2026-10-28。以下只依据已有本地文档、构建日志与产物元数据，不是上游 profile 清单。最终 0.1.3 基线下，三款均未重新游玩验证。**

**Reviewed 2026-10-28. This ledger uses existing local documents, build logs and artifact metadata, not the upstream profile list. None of these games has been revalidated through gameplay on the final 0.1.3 baseline.**

## 如何理解验证层级 / Evidence levels

| 层级 / Level | 能说明什么 / What it establishes |
|---|---|
| 历史打包 / Historical packaging | 构建日志明确完成，或有可核实元数据的导出产物。不能单独证明安装、启动、画面或可玩性。 / Explicit packaging completion or inspectable artifact metadata; not installation or playability. |
| 标题画面／有限运行 / Title screen or limited execution | 必须分别说明看到了什么。帧日志只能证明提交过帧，不能独立证明已进入标题画面或实际游戏。 / State the observation: frame logs alone do not identify a title screen or gameplay scene. |
| 用户正常游玩反馈 / User-confirmed gameplay | 已有文档明确记录用户反馈；仍不代表通关、长期稳定或其他平台成功。 / Recorded user feedback, not completion, long-term stability or another platform's validation. |
| 当前版本复验 / Current-release revalidation | 需明确当前启动器、上游基线、游戏版本、平台及实际操作。本次没有把历史记录升级为这个层级。 / Requires the current launcher/baseline, game version, platform and actual actions; historical records are not promoted to this level. |

## 成功打包清单 / Historical successful packaging

| 游戏 / Game | Title ID | 已核对版本 / Version | 打包证据 / Packaging | 运行证据 / Runtime | 0.1.3 |
|---|---|---|---|---|---|
| 塞尔达传说：智慧的再现 / The Legend of Zelda: Echoes of Wisdom | `01008CF01BAAC000` | **1.1.0 / `v196608`** | Mac 导出和 IPA 完成记录 / Mac export and IPA completion | 用户确认正常 Mac 打包游玩；另有有限操作／画面验证 / User-confirmed Mac gameplay and bounded input/rendering checks | **未重新游玩 / Not replayed** |
| 塞尔达传说：旷野之息 / The Legend of Zelda: Breath of the Wild | `01007EF00011E000` | **1.9.0 / `v1114112`** | nxnative IPA 完成；文档记录历史 Mac 导出 / nxnative IPA completion and documented historical Mac export | 独立 nxnative Mac 日志到第 2100 帧，SIGTERM 正常退出；有限运行 / Separate nxnative Mac log to frame 2100, graceful SIGTERM; limited execution | **未重新游玩 / Not replayed** |
| 集合啦！动物森友会 / Animal Crossing: New Horizons | `01006F8002326000` | **3.0.3 / `v2228224`** | IPA 完成、nxnative Mac App 元数据 / IPA completion and nxnative Mac metadata | 帧提交、DLC 枚举；含 `[RED]`，有限运行 / Frame submission and DLC enumeration with `[RED]` reports; limited execution | **未重新游玩 / Not replayed** |

未见记录支持的项目，不加入成功清单。没有把“标题画面”套用于仅有帧日志的结果。iOS 的 IPA 构建成功一律不表示真机安装／运行成功。

No unsupported titles are added. Frame logs are not relabeled as title-screen observations. An IPA completion record never implies iOS-device installation or execution.

## 智慧的再现 / Echoes of Wisdom

公开仓库内可追溯的文档：

- [Mac 修复与验收记录](echoes-of-wisdom-mac-repair.md)：2026-10-23 用户确认正常 Mac 打包游玩；有 110 秒隔离操作运行，第 3000／6000 帧检查心形 HUD、场景、提示及角色移动。测试由外部超时主动结束，不能把该 SIGKILL 当作游戏自身崩溃。
- [纹理修复报告](upstream-echoes-texture-views-pr-zh.md)：明确版本 **1.1.0、`v196608`**，Apple M2 Max / macOS，并明确没有 iOS 真机和全流程通关结论。
- [字体调查](echoes-of-wisdom-font-bringup.md)：记录更早的故障过程，不应将修复前的故障误写成最终结果，也不能用历史修复结果替代新版本验证。

本地核对还包括 `game/塞尔达传说-智慧的再现/01008CF01BAAC000_build/logs/build_ipa.log`：标注 1.1.0，使用 `extract/v196608`，有 `done` 结束记录。保留 App 的 `Contents/Info.plist` 版本为 1.1.0，bundle ID 为 `org.nxnative.01008cf01baac000.mac`。

The checked IPA log explicitly completes version 1.1.0 using `v196608`; retained Mac metadata identifies the nxnative bundle. The linked documents provide the strongest claim here: user-confirmed normal Mac packaging/play, alongside bounded rendering/input checks. Those historical binaries and upstream worktrees differ from the final 0.1.3 integration target. No whole-game, sustained-performance or iOS-device claim is made.

## 旷野之息 / Breath of the Wild

核对来源：

- 本地 `game/塞尔达传说-旷野之息/01007EF00011E000_build/logs/build_ipa.log` 明确是 `org.nxnative.01007ef00011e000`、1.9.0、`extract/v1114112`，记录 IPA 打包 `done`。
- [启动器方案历史记录](启动器方案.md)记载参数化 Mac 导出与 BotW 实测。这是历史开发记录，里面的旧命令不作为当前用法；当前流程见[最佳实践](打包最佳实践.md)。
- 同一 nxnative 工作目录的 `run-mac/boot.log` 有 nxnative 模块加载、NVN 帧统计，最后帧统计到 **2100**；末尾是 `received SIGTERM: graceful exit` 和 `graceful exit done`。本次核对未见 `[RED]`／`CRASH` 字样，但这不是完整功能与稳定性验收。该次日志还记录 **0 个 DLC**，不能用它证明 DLC 运行成功。

**排除混淆：**当前 `game/塞尔达传说-旷野之息/Breath of the Wild.app` 的 bundle ID 是 `org.macnativegames.botw`，旁边的 `BotW_build/` 也是另一条项目链。该 App、其帧率结果以及 **117 FPS** 记录都不作为 NxLauncher/nxnative 的验证依据。当前目录有同名 App 不足以证明来源。

The nxnative IPA log and separate `run-mac/boot.log` support historical packaging and limited Mac execution. The retained top-level app identifies **MacNativeGames**, so neither that app nor its 117 FPS result is attributed to NxLauncher. The inspected nxnative run reports zero DLC; DLC packaging and DLC gameplay must remain separate claims.

## 动物森友会 / Animal Crossing

核对来源：

- `game/集合啦动物森友会/01006F8002326000_build/logs/build_ipa.log` 明确记录 **3.0.3 / `v2228224`**、`org.nxnative.01006f8002326000`、IPA `done`，以及 DLC 索引 `1000 300 301`。
- 保留的 `Animal Crossing: New Horizons.app/Contents/Info.plist`：版本 **3.0.3**，bundle ID `org.nxnative.01006f8002326000.mac`。
- 本地 `~/Library/Application Support/nxnative/01006F8002326000/log.txt` 是多次运行累积日志，存在到第 **60000** 帧的历史记录；最后一段记录到第 **3000** 帧及约 30 FPS 的日志采样。这里不把采样值写成长期性能保证，也不推断是哪一段实际游玩场景。
- 运行日志有 `aoc: reporting 3 add-on contents {300,301,1000}`，路径指向该 nxnative App；同时整个日志有 **5 条 `[RED]`**，无 `CRASH` 字样。不能据此声称“零错误”“全程可玩”或“DLC 内容已实际完成游玩”。

The IPA completion log, bundle identity and runtime log support historical packaging plus limited execution and DLC enumeration. The runtime log spans multiple attempts and contains `[RED]` reports. Frame counts and sampled FPS do not establish scene identity, long-term stability, save round-trips or complete DLC functionality.

## 新增或升级记录的标准 / Adding evidence

每条新记录至少保留：启动器版本、上游精确 commit 与补丁状态、游戏 title ID 和更新版本、Mac/iOS 目标、系统／芯片、graphics API、构建会话、产物身份及实际检查项。将“打包完成”“标题画面”“进入游戏”“操作”“存档重载”逐项记录；未做就标未做。

For each new record retain launcher version, exact upstream commit/patch state, title/update, target, OS/chip, graphics API, session, artifact identity and actual checks. Record packaging, title screen, gameplay, input and save/reload separately; mark unperformed checks as such.

原始游戏、密钥、存档与完整日志保持本地。文档只摘录必要的非敏感事实；反馈前检查诊断包。以上本地路径是证据索引，不表示游戏资源随仓库发布。

Keep game data, keys, saves and raw logs local. These paths identify local evidence; they do not mean game resources ship with the repository. Review diagnostics before submission.
