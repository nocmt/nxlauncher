《塞尔达传说：智慧的再现》Mac 打包和游玩反馈，以及字体修复后的两项通用纹理视图修复。

感谢将 #55 以 `1765d53` 落入主线。用户现已实测反馈：**《塞尔达传说：智慧的再现》可以正常打包并游玩**。测试版本为 1.1.0（`v196608`，title ID `01008CF01BAAC000`），Apple M2 Max / macOS。这里报告的是 Mac 结果，不代表 iOS 实机或全流程通关验证。

本 PR 最终重放到提交期间新到达的最新 `main`：`8a4b1dc82073f9d8635bd51d634af681f5d71ee1`；保留其中 PR #62 的渲染优化，并重新通过两项 Metal 回归。字体修复已经在上游，因此不重复带入；只改 `nvn_mtl.m`、测试 Makefile，并新增两个使用合成纹理的回归测试，不包含游戏 profile、资源、字体、密钥或生成产物。

## 1. 约束采样纹理视图的 mip 范围

字体问题解除后，游戏创建一个 64×64、六层 array、七级 mip 的纹理视图，指定 base=1/count=7。基础 NVN 和 Metal 纹理都确实有七级，剩余有效范围为六级；直接把 `[1, 8)` 传给 Metal 会触发验证错误。

在构建视图前拒绝越界 base，并把 count 限制为 base 之后的剩余级数。正常范围保持不变。最大 mip 的裁剪与 [deko3d 的 Tegra descriptor writer](https://github.com/devkitPro/deko3d/blob/master/source/maxwell/tic_generate.cpp#L160) 一致；它是独立实现证据，不是 NVN 官方规范。越界 base 返回空绑定是防御处理，实际游戏观察路径未走此分支。

## 2. 组合纹理格式与 descriptor 的通道映射

可进入游戏后，心形 HUD 出现红色矩形底和暗心。遮罩使用 NVN RGB565，对应 Metal `B5G6R5Unorm`；现有 `nvn_fmt_to_mtl` 已返回所需 R/B 交换，但 `tex_by_id` 只使用 builder/view 的 swizzle，丢失了格式映射。

descriptor 选择的是 NVN 逻辑分量，因此最终映射应为 `format[descriptor[channel]]`。修复保留 ZERO/ONE 常量、view 优先于 builder 的行为，使用有效 view format 的映射；不支持的 view format 则沿用基础格式映射，与现有 pixel-format fallback 一致。组合后的映射进入原有 view-cache key。

同样使 RGBX 的 alpha-one 语义在采样时生效。没有修改格式表、游戏 shader、shader 翻译链或加入游戏专属分支。

RGB565 顺序的独立参考：[deko3d format traits](https://github.com/devkitPro/deko3d/blob/master/source/maxwell/format_traits.inc#L51)、[Mesa format definitions](https://github.com/chaotic-cx/mesa-mirror/blob/main/src/util/format/u_format.yaml#L281)、[ANGLE Metal format table](https://github.com/google/angle/blob/main/src/libANGLE/renderer/metal/mtl_format_table_autogen.mm#L242)。

## 验证

在上述最新上游基线上：

```sh
make -C dm/gfx/tests GAME=01007EF00011E000 t_view_levels t_view_swizzle
MTL_DEBUG_LAYER=1 dm/gfx/tests/t_view_levels
MTL_DEBUG_LAYER=1 dm/gfx/tests/t_view_swizzle
```

- mip 范围测试：34 checks，0 failed。覆盖默认/部分/超出剩余范围、最后一级、无效 base 和 array layers。
- swizzle 测试：156 checks，0 failed。走生产 `tex_by_id` 并实际读取 Metal GPU 输出，覆盖 RGB565/BGR565、常量组合、view/builder 优先级、RGBX alpha、双向格式覆盖、RGBA8/RG8 保持及不支持格式的回退。重复查询验证 registration cache；不宣称覆盖共享 serial 的全局 view-cache 复用。
- 修复前最初的通道测试复现 12 项失败；额外 fallback 测试复现 6 项失败。
- `GAME=01008CF01BAAC000` Mac host 编译成功，使用本地游戏 profile。
- 最终上游基线 `8a4b1dc` 加本 PR 的 host 完成 110 秒隔离操作验证，使用已打包游戏的本地资源；第 6000 帧再次确认心形、场景和操作提示正常，角色已移动到阶梯障碍前。测试由外部超时主动结束（`timed_out=true` / exit `-9`），不是游戏崩溃。用户已反馈可正常打包游玩。

完整测试套件未宣称通过：额外尝试现有 `t_pfv` 目标时发现 `nvn_sparse_*` 链接缺失；在未修改的同一上游提交上也独立复现，因此没有把这个既有测试构建问题混入本 PR。编译仍有现有 renderer 警告。

没有进行 iOS 设备测试。游戏后续全流程、其他 packed 格式（例如 RGB5/RGB5A1）和 Metal view 创建失败后的既有 fallback 行为未穷尽验证。
