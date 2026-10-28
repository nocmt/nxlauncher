# NxLauncher 第三方材料与再分发说明

本文件随每个公开包发布。它不是对上游项目许可证的替代；请同时保留各依赖包的原始文本。

## 本项目

NxLauncher 和本仓库发布脚本采用 MIT，见根目录 `LICENSE`。上游 `nxnative` 保留其自己的 MIT 和 `dm/third_party` 中的许可证文件。

## 已核对的运行时材料

| 材料 | 固定版本/来源 | 许可与包内位置 |
|---|---|---|
| CPython | python-build-standalone build `20260807`, CPython `3.13.15`, macOS arm64 | PSF-2.0 及其组件文本，`licenses/python-build-standalone-20260807/` |
| backports.zstd | 1.8.0 | PSF-2.0 与 zstd 文本，wheel 和 `licenses/wheel-backports.zstd-1.8.0/` |
| capstone | 5.0.9 | wheel 自带许可证，`licenses/wheel-capstone-5.0.9/` |
| fontTools | 4.67.0 | MIT及其外部材料，`licenses/wheel-fonttools-4.67.0/` |
| lz4 | 4.4.5 | BSD文本，`licenses/wheel-lz4-4.4.5/` |
| Pillow | 13.0.0 | MIT-CMU文本，`licenses/wheel-pillow-13.0.0/` |
| .NET DLL | Gommon 2.8.1.2, Humanizer.Core 3.0.10, Microsoft.IO.RecyclableMemoryStream 3.0.1, MsgPack.Cli 1.0.1, System.CodeDom 4.4.0 | 各自许可证和 NuGet 元数据，`licenses/`；DLL 字节由 `dll-inventory.json` 固定 |
| Noto Sans SC | google/fonts commit `ddf386ba1b9fbc6b2c818f1ddcd9148f54ced94b` | SIL OFL 1.1，`Scripts/fonts/OFL.txt`；原始字体 SHA-256 记录在 `provenance.json` |

许可证来源、哈希和局限由 `dependency-manifest.json` 与 `licenses/provenance.json` 记录。更新任何版本都必须重新核对上游来源、许可证和再分发条件，不能只替换文件名。

## 不随包发布的材料

游戏 NSP/XCI/NSZ/NCA、存档、密钥、个人配置、开发机路径、调试符号和商业系统字体均不属于公开包。游戏和主机密钥由用户在本机显式提供。默认字体只使用可再分发的 Noto Sans SC；用户显式设置 `NXLAUNCHER_FONT_PATH` 时生成结果标记为不可公开再分发。

## 预编译与签名限制

当前 `dmsh_xlate` 依赖的部分 DLL 是已验证字节来源的预编译产物，不声称本次发布可从源码完全重现。发布审核脚本必须通过后才可打包。macOS 包使用 Developer ID Application 签名时启用 hardened runtime；本预览包签名未公证、未 staple。没有明确凭据时不得调用公证服务。
