## 问题

`font_skip()` 用 SDK 版本以及 main 是否导入 `ScalableFontEngineHelper::Decode`，决定共享字体地址是否包含 BFTTF 头。导入存在，并不代表每条字体加载路径都会调用 Decode。

《塞尔达传说：智慧的再现》1.1.0（SDK 20.5.1）导入 Decode，但共享字体描述为 type 0，该路径直接把 `GetSharedFontAddress()` 返回的地址交给 `ScalableFontEngine::LoadFont`。目前 host 返回的八字节 BFTTF 头因此被当作 TTF 数据，字体加载失败，后续字形查询返回空指针并崩溃。

## 改动

仅在 `ScalableFontEngine::LoadFont(char*, const void*, unsigned, unsigned)` 入口做一层转发：

- 仅当数据指针**精确等于 host 自己创建的标准或扩展共享字体 allocation base** 时，传入 `base + 8` 的 TTF 数据。
- 通过 `guest_sym` 调用原 guest 实现，字体解析、错误状态及返回值仍由 SDK 处理。
- 已 Decode 的 `base + 8`、NULL、其他内部指针、游戏自己的字体数据全部原样转发，即使其他缓冲区含相同 magic 也不会处理。
- 不修改共享字体内容、`font_skip()`、Decode 或现有 profile override；不新增游戏 ID、build ID 或固定指令偏移。
- 两个 unsigned 参数分别是字体集合索引和输出名称缓冲区容量，均原样转发。

生产代码只改 `hle_sdk16.c`；另加一个无需游戏文件的回归测试，并接入现有测试入口。

## 验证

基于纯上游 `e18a9fd`，不含 NxLauncher 本地补丁；使用同一份已有导出模块和资源、相同 profile，以全新的临时 HOME、存档和缓存目录做对照：

| 观测点 | 未修改上游 | 本改动 |
| --- | --- | --- |
| 字体引擎初始化后的 GetError | 0 | 0 |
| 两处 LoadFont 后的 GetError，各 6 次 | 403 | 0 |
| SetFont 后的 GetError | 301 | 0 |
| 共享字体描述类型 | 六次均为 0 | 六次均为 0 |
| 条件 Decode 路径命中 | 0 | 0 |
| 原崩溃 `main+0x8b37c`，访问 `0x38` | 复现 | 已越过 |

403/301 是实测的字体引擎错误值，不将其命名为未确认的 SDK 枚举。

- `make -C dm/host/tests GAME=01007EF00011E000 run`：全部 15 个测试程序通过。
- 新增共享字体测试：137 项检查通过，覆盖真实 forced 注册、原函数只解析一次、精确所有权匹配、已 Decode 指针、无关同 magic 缓冲区、NULL、参数与返回值保持、扩展字体回退，以及原实现缺失时明确失败。
- Mac host 构建通过，修改源文件的 Mac / iOS arm64 严格语法检查通过。
- 《旷野之息》原版 / 修复版分别在全新存档目录运行 20 秒，均到达至少 900 帧，无崩溃；修复版已确认该 LoadFont 符号被绑定。此启动流程没有请求共享字体，因此这里只作为启动回归检查，不作为实际 Decode 消费路径的运行时证明。

## 范围与限制

这修复了共享字体进入 LoadFont 时的格式不匹配，**不代表《智慧的再现》已完整可玩**。越过字体崩溃后，它仍会在第 3 帧附近触发独立的 Metal texture-view mip 范围断言：请求范围终点为 8，而 texture 只有 7 个 mip；本 PR 不修改图形代码。

此转发使用已有 HLE_FORCE relocation 机制。模块内直接调用、其他重载或经 `nn::ro::LookupSymbol` 获得的原地址不在本次拦截范围内；不声称覆盖所有字体消费者。已 Decode 指针保持不变由组件测试验证，未将其描述为所有已适配游戏的实机回归。

没有提交游戏文件、字体、密钥、内存转储或生成的 profile，也没有改动着色器转换链。
