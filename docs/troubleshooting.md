# 排障指南 / Troubleshooting

[中文首页](../README.zh-CN.md) · [English README](../README.md) · [打包最佳实践](打包最佳实践.md) · [实测记录](tested-games.md)

适用于 NxLauncher **0.1.3** 的 Mac／iOS 目标。启动器界面主要中文，因此下面按界面与错误关键词查找。命令从准备好的源码仓库根目录运行；打包版用户优先使用编译环境、构建日志和诊断导出功能。示例中的路径、title ID、版本和会话 ID 需替换成实际值。

For English readers: the table below maps symptoms to recovery sections. Start with target-specific `doctor`, preserve the failed session, and review the diagnostic ZIP before sharing. Packaging success, runtime success and device installation are separate checks.

## 先确定卡在哪一步 / Find the failing stage

| 现象 / Symptom | 先做什么 / First action | 继续阅读 |
|---|---|---|
| 启动器打不开 / Launcher blocked | 先解压，确认下载来源与发布说明 | [macOS 拦截](#macos-拦截与签名) |
| 缺 Xcode／Metal／.NET / Toolchain failure | 对实际目标运行 `doctor` | [环境检查](#环境检查与依赖安装) |
| 终端正常、Finder 失败 / Finder differs | 检查诊断实际选中的工具与 Python | [Finder 与终端](#finder-与终端环境不同) |
| 游戏识别不对 / Wrong inputs | `plan` 核对本体、更新、DLC、title ID | [输入与密钥](#输入文件与密钥) |
| 没有 profile / Missing profile | 暂停把临时档案当兼容保证 | [支持范围](#没有-profile或图形-api-不明确) |
| 卡在着色器／链不匹配 / Shader issue | 留存日志，检查目标与 API，再考虑重建 | [构建与缓存](#构建慢缓存与着色器重建) |
| 导出失败 / Export failed | 检查目标、工作目录、版本与剩余空间 | [导出](#导出失败或产物不完整) |
| 黑屏、画面错误、崩溃 / Runtime issue | 看游戏 `log.txt`，区分构建与运行 | [运行](#黑屏花屏崩溃输入或声音异常) |
| 存档不见 / Missing saves | 同时检查新旧 Application Support 位置 | [存档](#存档或设置不见了) |
| IPA 装不上 / iOS installation | 核对签名、设备、描述文件与权限 | [iOS](#ios-签名安装与真机) |
| 无法自行定位 / Still unclear | 导出指定会话，查看 ZIP 再反馈 | [诊断与反馈](#诊断包内容检查与反馈) |

先记下**版本、目标、游戏更新、失败阶段与会话 ID**。保留第一次失败的日志；重复点击构建可能让定位更困难。先备份存档，不要用删除整个游戏目录或 Application Support 的方式试错。

## 环境检查与依赖安装

```bash
python3 Tools/pack_pipeline.py doctor --target mac
# 只有构建 iOS 时才检查这一组：
python3 Tools/pack_pipeline.py doctor --target ios
```

命令输出逐行 JSON：查看检查项的成功状态、detail 和修复提示。`doctor` 是检查入口；真正安装是独立操作。Mac 目标不应因缺少 iPhoneOS SDK 而失败；若发生，附上完整检查项和当前版本反馈，不要为 Mac 盲目安装 iOS SDK。

1. **Xcode 未选中或只有 Command Line Tools。**从 [Apple 官方入口](https://developer.apple.com/xcode/)安装完整 Xcode，打开一次完成初始安装、许可及必要组件。查看当前选择：

   ```bash
   xcode-select -p
   xcodebuild -version
   xcrun --sdk macosx --find clang
   xcrun --sdk macosx --find metal
   xcrun --sdk macosx --find metallib
   ```

   若路径指向 `CommandLineTools`，或不是要用的 Xcode，在 Xcode Settings 的 Locations 中选择对应 Command Line Tools。也可在确认安装位置后执行下式；该命令会更改系统开发者目录并可能要求管理员授权：

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. **Metal 工具缺失。**在 Xcode Settings 的 Components 中安装当前 Xcode 提供的 Metal Toolchain，再重复 `xcrun` 检查。iOS 目标另查 `xcrun --sdk iphoneos --show-sdk-path`；Mac 不需要这一步。
3. **Homebrew 未安装。**使用 [brew.sh](https://brew.sh/) 的官方指引，完成后重新打开启动器并检查环境。应用不会代替用户运行来源不明的 Homebrew 引导命令。
4. **缺少 brew 包。**界面可以对固定白名单内的工具提出安装操作，显示命令后由用户确认。只安装实际检查提示的包；不要将日志中的任意命令当作可自动执行的安装器。
5. **.NET 不兼容。**需要 **arm64 .NET 10 SDK 和运行时**；只有 .NET 11、只有 SDK 路径或 x64/Rosetta 安装都不足以通过完整检查：

   ```bash
   dotnet --info
   dotnet --list-sdks
   dotnet --list-runtimes
   ```

   按当前诊断建议安装，例如允许的 `dotnet@10`，或使用 [.NET 10 官方下载](https://dotnet.microsoft.com/download/dotnet/10.0)。运行根目录应包含真正的 `dotnet`，不是 `bin` 文件夹。修正后重新检查，尤其要确认 apphost/runtime 解析项通过。
6. **Python 模块缺失。**源码方式先运行 `./bootstrap.sh`，它建立 `.venv`，不要向系统 Python 混装依赖。核对所选解释器：

   ```bash
   .venv/bin/python3 -c 'import lz4, capstone, fontTools, PIL; print("imports OK")'
   ```

   还需 zstd 支持：Python 3.14 可用 `compression.zstd`，较早版本使用 `backports.zstd`。打包版使用自带 Python；若初始化失败，保留启动日志并确认应用已完整解压、用户缓存目录可写。

完成修复后重新运行对应目标的 `doctor`，再开始构建。下载工具或包的失败不应通过关闭系统安全机制解决。

## Finder 与终端环境不同

启动器会补充常见 GUI PATH，并探测 .NET 根目录；Finder 不会读取终端的 shell 初始化文件。出现差异时：

- 比较诊断选择的 Python、`dotnet` 路径、架构与 SDK／运行时，而不是只看终端的 `which` 结果。
- 检查自行设置的 `NXLAUNCHER_PYTHON`、`NXLAUNCHER_REPO`、`DOTNET_ROOT_ARM64`、`DOTNET_ROOT` 是否仍有效。不要贴出整个环境变量表，其中可能有凭据。
- 源码仓库移动后重新运行 `./bootstrap.sh`；不要复制旧虚拟环境后假定里面的路径已更新。
- 更新打包版后确认运行的是新 `NxLauncher.app`。工具缓存位于 `~/Library/Caches/NxLauncher/home`，它不是存档目录。若怀疑缓存损坏，先退出启动器、保存诊断，将该 `home` 目录改名备份，再启动以重新初始化；不要在构建时移动它。

## 输入文件与密钥

先检查识别结果：

```bash
python3 Tools/pack_pipeline.py plan --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
```

| 问题 | 处理方法 |
|---|---|
| 未找到本体 | 每个文件夹只放一款游戏，保证直接包含本体 NSP 或 XCI，而不是只放更新或套一层目录。 |
| 更新被认成本体 | 核对文件名中 `[16 位 title ID]`；本体一般以 `000` 结尾，更新以 `800` 结尾。不要仅凭文件名猜测实际包内容。 |
| 多个不相关更新 | 移出不属于这款游戏的包，核对实际选中的版本。UI 能列出多个文件不等于任意组合均兼容。 |
| DLC 未识别 | 检查所属游戏、文件名标记（如 `[DLC]`）、解包日志及导出资源。挂载枚举成功与 DLC 功能可玩是两项验证。 |
| `keys_ok` 为真但解包失败 | 它首先只能说明路径存在；继续看解包日志的密钥代际、权限、包完整性提示。不要把密钥内容粘贴出来。 |
| 文件存在但不可读 | 在 Finder 检查访问权限、外置盘连接、云端文件是否真正下载完成，以及磁盘剩余空间。 |

密钥需由用户合法自备，放在独立位置。不要上传密钥、试图从错误报告获取他人的密钥或将密钥塞入诊断包。本项目不提供来源；流水线不需要额外输入固件。

## 没有 profile，或图形 API 不明确

```bash
python3 Tools/pack_pipeline.py games
python3 Tools/pack_pipeline.py plan --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
```

`games` 列的是移植档案。没有档案时，上游可能生成 survey／临时 profile；这属于移植工作的起点，不能保证启动。已有档案也可能只覆盖某个版本。不要用另一款游戏的内存配置或 shader 表代替。

图形选择为 `auto|nvn|vulkan|gl`，用于 `build`、`doctor`、`export`（`plan` 不接受该参数）。先保留 `auto` 的检测结果，只有在明确知道游戏路径、上游说明或诊断要求时再指定。该选项不是宿主 GPU 厂商选择，也不是“换一个就必定修好”的开关。切换后保存新的会话与错误，不要混用旧结果作为验证。

## 构建慢、缓存与着色器重建

首次解包、代码重写、着色器翻译和 Metal 编译可能耗时较长。先看当前阶段、工作目录 `logs/` 的更新时间，以及是否仍有编译进程；不要只凭进度条不动判定卡死。耗时因游戏、芯片、存储与缓存而异。

建议按顺序处理：

1. 留存失败会话、最后错误和阶段日志，检查磁盘空间与 `doctor`。
2. 确认 title ID、更新版本、目标及 graphics API 未变化，重试一次正常构建。
3. 错误明确指向复用的构建状态时，显式重建：

   ```bash
   python3 Tools/pack_pipeline.py build --target mac --rebuild \
     --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
   ```

4. 错误涉及 shader chain／metallib／旧着色器时，保留原日志后重建着色器：

   ```bash
   python3 Tools/pack_pipeline.py build --target mac --rebuild-shaders \
     --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
   ```

重建会重做相应阶段，可能覆盖生成产物并花费大量时间。不要手动改 shader chain 标记来绕过校验；这会隐藏真实的不一致。不要在脚本执行期间原地修改脚本或移动工作目录。

若持续在同一阶段失败，停止重复重建，导出该会话诊断。`SIGKILL`、退出 `-9` 需要结合超时、用户取消和系统内存压力判断；历史自动化测试主动超时并不等于游戏崩溃。

| 结构化错误码 | 下一步 |
|---|---|
| `NX_DEPENDENCIES` | 重跑对应目标 `doctor`，修复第一个失败项。 |
| `NX_INPUT_INVALID` | 核对输入、keys 路径、仓库与输出目录。 |
| `NX_BUILD_FAILED` | 查看会话与首个失败阶段，修复后用原目录重试。 |
| `NX_EXPORT_FAILED` | 核对完整工作目录、版本、磁盘与新导出路径。 |
| `NX_MANIFEST_INVALID` | 用 `build --target mac`（或 `ios`）加 `--rebuild` 重新生成完整构建，不手改清单。 |
| `NX_RUNTIME_CAPTURE_REQUIRED` | 当前构建不会自动启动游戏采集；按对应上游游戏说明手动准备所需捕获缓存后重试。 |
| `NX_INTERRUPTED` | 保留中断会话，原参数重试，已完成提取可保留。 |
| `NX_INTERNAL` | 保留完整错误与会话，导出诊断反馈。 |

## 导出失败或产物不完整

`plan/build/doctor --target mac|ios` 与 `export --target mac-app|ios-ipa|ios-ipa-unsigned` 是两组不同接口。Mac 构建成功默认自动导出，不自动启动；只生成 IPA 不表示 Mac 导出也已完成。

检查以下项目：

- `--work` 必须对应当前 title ID 的工作目录，`--ver` 对应实际 `extract/v…`、`patched_v…` 版本；不要直接照抄示例的 BotW ID。
- `--out` 使用可写位置，并预留一份完整产物的空间。复制游戏资源可能很大。
- 缺 `patched`、RomFS、metallib、profile／shader 表时，回到构建阶段修复；不要从不明旧产物拼装目录。
- Mac 导出因 chain 不一致失败时重建对应着色器和宿主，再导出。不要只重命名文件。
- Xcode、签名或字体阶段失败时，以该步骤日志为准。默认使用开放 **NotoSansSC** 路径，helper 已本地验证；字形缺失仍需记录游戏、语言和场景，不要上传专有字体作为修复附件。

Mac 本地结构检查（把路径替换成实际产物）：

```bash
plutil -lint "$HOME/Desktop/MyGame.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$HOME/Desktop/MyGame.app"
codesign -dv --verbose=4 "$HOME/Desktop/MyGame.app"
```

这些检查不能证明可玩或已公证。导出失败后不要把残留目录当成可用产物。更改 App 内容后必须重新处理签名。

## macOS 拦截与签名

协调者确认已有 Developer ID、无公证凭据，本次计划交付 **0.1.3 Developer ID 签名、未公证 preview**；实际下载资产的签名验收以最终发布清单为准。**本地 ad-hoc 校验、Developer ID 签名、Gatekeeper 评估、Apple 公证是不同事情。**

1. 从项目 Release 获取启动器，完整解压，核对发布说明及其提供的校验信息。
2. 对被拦截的实际 App 运行只读检查：

   ```bash
   codesign -dv --verbose=4 "/Applications/NxLauncher.app"
   codesign --verify --deep --strict --verbose=2 "/Applications/NxLauncher.app"
   spctl --assess --type execute --verbose=4 "/Applications/NxLauncher.app"
   ```

3. 若来源或完整性无法确认，重新下载并核对资产；若是已确认可信、但未公证的本地导出，按 [Apple 官方指引](https://support.apple.com/102445)在隐私与安全设置中处理系统提示。
4. 不要关闭全局 Gatekeeper，不要对整个下载目录递归移除安全属性。若签名校验失败，保存错误并重新构建／导出；不能用强行放行替代完整性修复。

## 黑屏、花屏、崩溃、输入或声音异常

先区分“导出成功”与“运行成功”。在游戏对应目录查看：

```text
~/Library/Application Support/nxnative/<TITLE_ID>/log.txt
```

旧 App 可能使用按 App 名命名的目录。用 UI 显示的支持目录定位，确保看的是这次运行的日志而不是另一个项目的同名游戏。

1. 记录是在启动、标题、载入、进入场景还是操作后发生；保存错误前后少量日志。
2. 查看 `[RED]`、`CRASH`、`fatal`、缺资源、shader、内存分配或签名错误，但不要将“没有这些字样”当作完整验收。
3. 先恢复正常帧率／默认设置，排除自定义 `env.txt`。备份后改名该文件再试，**不要动 `save/`**。不要跨游戏照抄内存参数。
4. 输入问题先检查窗口焦点与控制器是否被系统识别；区分游戏按钮提示、控制器位置映射和鼠标／触摸模拟。逐次只改一个设置，记录具体设备和现象。
5. 画面问题使用 `auto` 重现并核对游戏更新、上游档案及着色器链；必要时按前文重建。可选截图应裁掉个人路径与通知，只展示定位问题所需画面。
6. 声音问题检查系统输出设备、音量及是否发生后台暂停；记录恢复前台后的行为。

有帧统计不代表画面正确；到达标题画面不代表进入游戏；能操作不代表存档可用。对照[实测记录](tested-games.md)确认你的版本是否有相应证据。

## 存档或设置不见了

当前导出通常使用：

```text
~/Library/Application Support/nxnative/<TITLE_ID>/save/
~/Library/Application Support/nxnative/<TITLE_ID>/env.txt
```

旧导出可能使用 `~/Library/Application Support/<旧 App 名>/`。改名旧 App 也可能改变其识别路径。先退出游戏，分别备份新旧支持目录，再确认当前选择 App 的真实 title ID 与布局。

迁移会尝试保留已有同名文件，不覆盖不等于自动解决存档冲突。若旧目录仍在，不要急于删除；确认最新存档并完成一次读档／保存／退出／重开后再整理。不同游戏版本的存档兼容性也需要验证。

游戏库条目删除只移除引用。重新添加原目录即可恢复引用；它不会从已删除的磁盘文件中重建存档。

## iOS 签名、安装与真机

- 先通过 `doctor --target ios`。本项目的运行验证使用真机路径，不能将模拟器当作等价验收环境。
- `ios-ipa-unsigned` 不可直接当作已签名安装包；`ios-ipa` 也需要当前环境具备合适身份与描述文件。
- 核对应用 bundle ID、证书、描述文件、目标设备、系统兼容性、签名有效期及所需 entitlements。不要只看 `codesign` 返回成功。
- 资源与 DLC 应在最终签名前放入包。修改签名后资源会破坏封印。
- 重签工具可能更改或移除权限；安装成功但运行失败时，查看设备安装／崩溃日志与最终权限。免费账号、付费账号及工具的具体限制以 Apple 与对应工具当前规则为准。
- `increased-memory-limit`、`extended-virtual-addressing` 等权限是否可用，取决于所选签名／描述文件和系统支持；不能在文档中保证任意侧载方式都保留。

反馈时可附去标识后的错误、bundle ID 与相关权限名，不附私钥、证书密码、完整描述文件或个人设备标识。历史 IPA 打包记录不是 0.1.3 iOS 真机成功证明。

## 诊断包内容、检查与反馈

```bash
python3 Tools/pack_pipeline.py diagnostics --out "$HOME/Desktop/NxLauncher-diagnostics.zip"
# 针对某一次失败，替换 SESSION_ID：
python3 Tools/pack_pipeline.py diagnostics \
  --out "$HOME/Desktop/NxLauncher-session.zip" --session SESSION_ID
```

诊断 ZIP 固定包含 `system.json`（系统、系统版本、架构、Python 版本）；选中会话中存在的 `session.json`、`events.jsonl`、`subprocess.log` 会放入 `session-0/`。不指定 `--session` 时选择最近一次其他会话，不自动收集整个历史。会话目录默认为 `~/Library/Application Support/NxLauncher/Pipeline/sessions/<SESSION_ID>/`，可由 `NXLAUNCHER_STATE_DIR` 更改状态根目录。指定会话找不到时，包可能只有系统信息，务必检查清单是否包含预期会话。

收集使用固定文件名白名单，不递归遍历游戏／工作目录。可选 `--launcher-log FILE` 仅收集显式指定的普通 `.log`／`.txt`／`.jsonl` 文本文件，最大 32 MiB；界面导出也会带入启动器会话日志。工具检查与错误上下文可能出现在事件中，但不会自动附上所有阶段日志或游戏运行日志。具体字段参见[隐私说明](privacy.md)。不应加入游戏包、RomFS、密钥内容、存档或签名凭据；**脱敏不是绝对保证**，自由文本日志仍可能出现用户名、个人路径、设备或环境信息。

分享前按顺序检查：

1. 用归档工具查看 ZIP 文件名清单，也可运行：

   ```bash
   unzip -l "$HOME/Desktop/NxLauncher-diagnostics.zip"
   ```

2. 解压到新文件夹，用文本编辑器检查日志和 JSON：个人用户名、绝对路径、邮箱、设备标识、环境变量、密钥路径和凭据是否出现。
3. 移除无关信息后重新压缩，保留错误上下文与版本信息。不要上传整个 `_build` 目录。
4. 反馈包含下列模板；仓库公开后使用 [Issues](https://github.com/nocmt/nxlauncher/issues)，公开前使用既有私有协作渠道。

```text
NxLauncher: 0.1.3（注明实际构建来源）
目标: mac / ios
系统和芯片:
游戏 title ID / 显示版本 / v数字版本:
graphics-api: auto / nvn / vulkan / gl
上游基线及补丁状态（若已知）:
失败阶段 / 会话 ID:
复现步骤:
预期行为 / 实际行为:
最后一条有意义的错误:
是否正常重试 / rebuild / rebuild-shaders:
诊断 ZIP 已检查并去除个人或受保护数据: 是 / 否
```

不要把日志中的安装建议当作来自维护者的自动授权。能稳定复现时，保留同一输入与设置，让报告可以由他人依据文档操作复查。
