# NxLauncher 发布流程（0.1.2）

发布有两条路径：本机用自己的 Developer ID 构建并手动上传；标签 CI 自动构建 **ad-hoc 签名、未公证、未 staple** 的 GitHub prerelease。两者不能混称。0.1.2 已在本地完成 Developer ID 签名、未公证的构建与验收；**公开与上传当前暂停**，原因见文末“公开暂停（2026-10-28）”。CI 面向后续标签自动发布；已经存在的同名 Release 不会被 CI 覆盖。

## 输入与边界

- `VERSION` 是版本来源，内容必须是 `MAJOR.MINOR.PATCH`；标签必须严格为 `v$(cat VERSION)`，指向包含全部发布源码的提交。
- `nxnative` 子模块提交必须与 `patches/base-commit` 完全一致。`patches/series` 定义补丁顺序；以 `Tools/prepare-nxnative.py` 的实际树验证为准，不在本文复制容易过期的 tree hash。
- 新 checkout 首先运行 `python3 Tools/prepare-nxnative.py` 应用补丁，再运行 `python3 Tools/prepare-nxnative.py --check`。只运行 `--check` 无法准备未打补丁的子模块。`--check --export NEW_DIRECTORY` 导出核验过的 Git blob，不复制本机忽略文件或构建残留。
- 打包 Python 固定为 **CPython 3.13.15 / python-build-standalone 20260807 / macOS arm64 / 普通 GIL ABI**，匹配 `Resources/wheels` 中的 cp313 wheels。CI 下载 `cpython-3.13.15+20260807-aarch64-apple-darwin-install_only.tar.gz`，SHA-256 固定为 `ebcf53fe921c356ad2eecfcea370cb744e7bd96fdef41a53e1e8f32a15c6dfeb`。
- 上游下载地址为 `https://github.com/astral-sh/python-build-standalone/releases/download/20260807/cpython-3.13.15%2B20260807-aarch64-apple-darwin-install_only.tar.gz`。该归档本身没有 `BUILD` 文件；CI **先验证上述归档摘要**，再在解包副本中写入 `BUILD=20260807`，满足发布脚本契约。更新 Python、BUILD、摘要和对应许可证必须一起审阅。
- 发布包不得包含游戏、`prod.keys`、`title.keys`、存档、备份、凭据、用户配置或 Git 元数据。不得把这些内容放入 staging，不得上传整个 `dist` 或仓库目录。测试使用生成的 fixtures，不启动游戏。
- 依赖和许可证由 `THIRD_PARTY_NOTICES.md`、payload 内的 `dependency-manifest.json` 和 `licenses/` 提供。自动审计不替代许可证审阅。

## 本机构建与验证

在已审阅的发布提交上操作，确认工作树干净，递归初始化子模块，并按上述顺序准备补丁。`bootstrap.sh --check --target mac` 用于已有 `.venv` 和完整游戏编译工具链的开发环境；它不安装 Python/.NET/图形工具，也不能直接作为空白 CI runner 的第一步。发布 app 的 CI 使用下述专用准备步骤。

```sh
git submodule update --init --recursive
python3 Tools/prepare-nxnative.py
python3 Tools/prepare-nxnative.py --check
python3 -m unittest discover -s Tests -v

# 指向已经核实版本、BUILD 与 arm64 架构的独立 Python 安装。
export NXLAUNCHER_PYTHON_ROOT="$HOME/.local/share/uv/python/cpython-3.13.15-macos-aarch64-none"
# 按本机 security find-identity 输出填写自己的证书，不要复制其他发布者身份。
export DEVELOPER_ID='Developer ID Application: YOUR NAME (TEAMID)'
export CODESIGN_TIMESTAMP=none
version=$(tr -d '\n' < VERSION)
zip="$PWD/dist/NxLauncher-${version}-macos-arm64.zip"
bash Scripts/make-release.sh "$zip" --identity "$DEVELOPER_ID" --python "$NXLAUNCHER_PYTHON_ROOT"
```

`Scripts/make-release.sh [zip] [--identity ID] [--python ROOT] [--package-only]` 是完整发布入口：调用 `make-app.sh` 构建 release Swift app，后者调用 `make-home-archive.sh` 导出已核验的补丁源码、Tools、fonts、wheels 和 Python；随后在 staging 解包 payload，修正安装机路径、核对许可证和 DLL/wheel 版本、由内到外重签 Mach-O、重新生成 wheel `RECORD`，审计 payload 和 app，再打 ZIP。`--package-only` 只对明确指定的已有 app 副本重新打包，CI 不使用它，也不使用本地旧 app 或缓存 payload。

`--python`/`NXLAUNCHER_PYTHON_ROOT` 必须贯穿归档和发布步骤。为兼容仍使用 uv 发现逻辑的旧脚本，CI 将安装位置设为 `$HOME/.local/share/uv/python/cpython-3.13.15-macos-aarch64-none`，并显式传递 `--python` 和环境变量。没有写死发布者 home 或 `/Users/runner` 路径。测试依赖装在独立 venv，不污染要打包的 Python。

ZIP 同文件系统原子替换；已有 app 则由 `make-app.sh` 使用 macOS `RENAME_SWAP` 原子交换。失败时保留旧输出，不先删除旧包。ZIP 与两个 sidecar 的发布不是一个多文件原子事务，因此上传前必须重新核对三者摘要。

产物命名严格为：

```text
NxLauncher-0.1.2-macos-arm64.zip
NxLauncher-0.1.2-macos-arm64.zip.sha256
NxLauncher-0.1.2-macos-arm64.zip.manifest.json
```

不要误用没有 `.zip` 中缀的 manifest 文件名。脚本旧版本生成的 `.sha256` 可能含已清理的 staging 绝对路径；上传前核对原摘要、ZIP 和 manifest 一致后，用 ZIP 文件名重新生成便携 sidecar，再在产物目录运行 `shasum -a 256 --check`。CI 会自动验证并规范该 sidecar，不改签名 ZIP 字节。

```sh
# 在 dist 内执行，使摘要文件只记录公开 ZIP 文件名。
(cd dist && shasum -a 256 "NxLauncher-${version}-macos-arm64.zip" \
  > "NxLauncher-${version}-macos-arm64.zip.sha256")
(cd dist && shasum -a 256 --check "NxLauncher-${version}-macos-arm64.zip.sha256")
```

## 签名等级与审计范围

- **本机 Developer ID 预览**：使用发布者 Keychain 中实际可用的 Developer ID Application 证书和 hardened runtime；当前 0.1.2 未公证、未 staple。上传说明和 manifest 必须如实记录实际身份和状态。
- **CI ad-hoc 预览**：`DEVELOPER_ID=-`、`CODESIGN_TIMESTAMP=none`，无需 Apple secrets。Release 标题、说明和 `release-provenance.json` 均注明 ad-hoc、未公证。不声称是 Developer ID 发布，也不执行 `notarytool`。
- `codesign --verify --deep --strict` 验证签名结构和内容完整性，不证明 Apple 公证或游戏兼容性。Gatekeeper 可能阻止未公证预览；`spctl --assess --type execute --verbose=4` 仅反映本机评估。
- `Tools/release-audit.py` 扫描公开 payload/app 的白名单、归档逃逸、游戏/密钥/存档格式、凭据、个人绝对路径和 `.pdb` 等；结果记录每个文件的 SHA-256。CI 额外扫描最终 ZIP 及嵌套归档，检查顶层目录、重复/不安全 ZIP 路径、符号链接、文件大小，再解包验证签名、app 版本和 arm64 架构。
- manifest 包含版本、架构、签名身份、公证/staple 状态、ZIP 大小及 SHA-256、app/payload audit。CI 的额外 `release-provenance.json` 绑定标签、源码提交 SHA、upstream pin、补丁摘要、PBS 归档摘要、运行链接及三个产物的摘要。不将该文件描述为 Apple 公证或第三方独立证明。

## 标签自动发布 CI

`.github/workflows/release.yml` 在推送 `v*.*.*` 标签时运行；内部再严格验证 `vMAJOR.MINOR.PATCH`，拒绝与 `VERSION` 不符的标签。CI 分成只读构建和具有 `contents: write` 的独立发布 job。

1. 构建 job 使用标准 `macos-15` Apple Silicon runner，并断言 `uname -m == arm64`。当前官方标签映射见 [GitHub runner 文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)；`macos-15-intel` 不适用。打印实际 Swift/Xcode 版本。
2. checkout 目标标签并递归初始化子模块，校验 HEAD、标签解引用的提交和触发 SHA 一致，检查顶层工作树干净，拒绝已有 app/payload 缓存。
3. 校验摘要并安装精确 PBS。应用补丁，运行 `--check` 和全新目录 `--export`；在隔离 venv 内从本仓库 wheels 离线安装测试依赖。
4. 运行 `Tests` 下全部 Python unittest，以及 `GameLibraryTests`、`SwiftSafetyTests`、`PipelineFailureTests`、`BuildLogViewTests` 四个独立 Swift harness。当前 `Package.swift` 没有 test target，故这里不使用无法覆盖这些 harness 的 `swift test`。
5. 显式调用 `Scripts/make-release.sh --identity - --python ...` 构建实际可分发 app ZIP，随后验证 manifest、SHA、签名和最终归档扫描。再次核验补丁树和顶层源码未被构建改变。
6. 仅保存 ZIP、`.zip.sha256`、`.zip.manifest.json`、`release-provenance.json` 四个资产。Actions artifact 保留 14 天；实际 GitHub Release 资产独立保存。
7. 发布 job 再 checkout 同一标签、下载该次构建的 artifact，复核源码 SHA、版本和全部资产摘要，然后执行 `gh release create --verify-tag --prerelease --latest=false`，实际创建可见 GitHub prerelease 并上传四个资产。不会设置为 latest，不自动创建缺失标签。

只需要仓库自动提供的 `GITHUB_TOKEN` 具有发布 job 的 `contents: write` 权限；不需要额外 PAT、Apple ID 或证书 secret。组织策略若禁止 Actions 写 Release，发布 job 会明确失败。

也可从 Actions 页手动运行 `workflow_dispatch`，必须同时提供已有 `tag` 和它解引用后的完整 40 位 `source_sha`。命令示例：

```sh
tag="v$(tr -d '\n' < VERSION)"
sha=$(git rev-parse "refs/tags/$tag^{commit}")
gh workflow run release.yml -f tag="$tag" -f source_sha="$sha"
```

手动触发走相同的源码构建、审计和 prerelease 流程，不从本机上传预生成资产。workflow 必须已经存在于默认分支，标签提交也应包含本发布实现。首次公开与本次 0.1.2 的 Developer ID 资产按下面的手动流程处理。

同一标签的运行串行排队，不取消已进行的构建。**如果同名 Release 已存在，创建会失败，不覆盖手动 Developer ID 资产，不执行 `--clobber`。** 如果一次发布因网络中断留下 draft 或部分资产，先检查 Release 的状态、签名类型和摘要，再由发布者处理该 draft；直接重跑不会静默覆盖它。

## 本次 0.1.2 手动 Developer ID 上传

本机产物已签名但未公证；发布说明必须写明 “Developer ID signed; not notarized; not stapled”，并核对实际证书身份。发布前从最终 ZIP 解包，运行 app audit 和 `codesign --verify --deep --strict`，核验 manifest 的版本/摘要/签名身份，确认对应源码已提交，标签指向该提交。只上传下面列出的三个公开产物。

```sh
version=$(tr -d '\n' < VERSION)
tag="v$version"
sha=$(git rev-parse "refs/tags/$tag^{commit}")
gh release create "$tag" \
  "dist/NxLauncher-${version}-macos-arm64.zip" \
  "dist/NxLauncher-${version}-macos-arm64.zip.sha256" \
  "dist/NxLauncher-${version}-macos-arm64.zip.manifest.json" \
  --verify-tag --target "$sha" --prerelease --latest=false \
  --title "NxLauncher $version — Developer ID preview (not notarized)" \
  --notes 'macOS arm64 preview. Developer ID signed; not notarized; not stapled. No games, keys or saves included.'
```

如果已创建 Release，使用 `gh release upload "$tag"` 并逐一列出上述三个文件；不使用 `dist/*`，不使用 `--clobber` 替换未知资产。为避免标签 CI 先创建 ad-hoc 同名 Release，可在标签尚未推送时先以目标 SHA 创建并上传 **draft**，再推送标签，核验 tag/SHA 后由发布者公开 draft；或者先合并 CI、使用新版本标签开始自动发布。已有 Release 的保护不依赖其是 draft 还是公开状态。

## 历史审计

`python3 Tools/release-audit.py --root . --kind history` 检查本地可达 Git refs 的对象：真实密钥、游戏/密钥/存档路径是阻断；无凭据的旧开发路径警告不能视为源码或资产泄密扫描通过。该命令不改写历史，也不覆盖远程不可达对象或图片 OCR。首次公开前应单独运行并审阅结果，不能用 CI 的产物审计代替。发现真实秘密时停止发布、撤销密钥并处理历史。

## 公开暂停（2026-10-28）

2026-10-28 的公开检查结果：源码审计、构建产物审计和可达历史扫描都没有发现密钥值、密码或游戏数据载荷；但把历史中每个 `docs/screenshot.png` 版本导出后逐张目视检查，发现 **四个旧版本含第三方游戏封面美术**（封面缩略图，不是游戏运行画面）。按“禁止游戏内容入库／公开”的边界，这些 blob 不能随仓库一起公开，因此本次停止公开、推送和发起 Release，仓库继续保持私有。当前工作树中该截图已删除，但删除不会移除历史对象。

| 历史 blob | 目视结论 |
|---|---|
| `4d39f51116ff574cf5e899ba0d2b7283f7da5dd1` | 启动器界面；含游戏封面缩略图与开发机绝对路径；无密钥值、无运行画面 |
| `4cab187ee6752b105f93198df863ccd8e0071661` | 同上 |
| `c77ce93cae5f21781062427047f785480c07958d` | 较早界面；含封面缩略图、开发机路径、游戏文件绝对路径；无密钥值 |
| `99c76ac061a2fb71a25169a420d77c189ad28db3` | 同上 |

可选处理（都需要仓库所有者决定，发布脚本不会自动执行）：

1. **保持私有**，只分发本地签名 ZIP（当前状态）。
2. **用全新历史的单次提交公开**：新建孤立分支或新仓库，只推入当前已审阅的源码快照，使上述 blob 不在可达历史中；本仓库原历史保留在本地。这不是在不改历史的前提下公开。
3. **重写历史移除该文件**（`git filter-repo --path docs/screenshot.png --invert-paths`），随后强制推送并通知协作者重新克隆。只有在明确接受改写历史时才采用。

任何选项完成后，都需要重新运行 `Tools/release-audit.py --kind history`，并对导出的历史截图再次目视检查，才能继续下面的手动上传流程。旧截图目视检查属于人工步骤，自动审计的正则扫描不能替代。

