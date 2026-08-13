# Debug Session: cover-animation-jitter

- **Status**: [OPEN]
- **Issue**: 角色个人空间快速滑动到底部时，封面高度出现抖动（此前已尝试 AnimatedContainer→显式 AnimationController 两种方案，仍未解决）
- **Debug Server**: http://127.0.0.1:<port>/event
- **Log File**: .dbg/trae-debug-log-cover-animation-jitter.ndjson

## Reproduction Steps

1. 打开角色个人空间（CharacterDetailScreen）
2. 朋友圈列表快速滑动到底部（含在底部继续下拉/反弹）
3. 观察封面背景图高度是否抖动 / 卡住循环

## Hypotheses & Verification

| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | 底部 overscroll 橡皮筋振荡直接驱动封面高度（pixels 往复 → shrink 往复） | ~~High~~ → **Rejected** | Low | pre-fix 日志 5-26 行：out:true 期间 `sh` 恒为 259.885（shrinkMax 饱和）、封面目标高度恒为 86.63（minHeight），pixels 在 870-1736 往复但封面高度完全不变 |
| B | 封面高度变化导致 ListView viewport 高度变化，ScrollPosition 反向调整产生反馈滚动 → 抖动 | ~~High~~ → **Rejected(overscroll 期)** | Low | overscroll 期封面高度恒定 → viewport 恒定，无反馈；仅 pixels 0→260 起步段有单次收缩（跟手预期），非抖动来源 |
| C | ScrollEnd 后吸附动画与残留滚动/布局调整竞争，动画被反复取消重启 | ~~Med~~ → **Rejected** | Low | 全部 settleCover 均为 `expanded:false, target:86.63, rendered:86.63`，playSettle `from==to`（<0.5px）**从未真正播放**吸附动画；无动画可竞争 |
| D | 滚动回调每帧 setState 重建整页，overscroll 振荡期掉帧/布局抖动 | Med → **Confirmed** | Low | 修复前滚动回调**无条件 setState**（每帧整页重建），而 overscroll 期封面状态恒不变 → 数百毫秒橡皮筋回弹全程空转重建 → 掉帧抖动；**修复后 A 事件新增 `set` 字段**，预期 overscroll 期 `set:false`（无重建） |

## Log Evidence

### pre-fix（runId: pre-fix，152 行）

- 第 5-26 行：进入底部 overscroll（`out:true`），pixels 1300→1736→1301 往复，`sh` 恒 259.885、封面高度恒 86.63 → **封面不随橡皮筋振荡移动**（假设 A 拒绝）
- 第 27-29 行：ScrollEnd(p=1301) → settle(target=86.63) → playSettle(from==to) 跳过 → **吸附动画从未播放**（假设 C 拒绝）
- 第 30-55 行：用户再次触摸（drag:true）继续推入 overscroll（p 至 1736）再松手（drag:false）惯性回弹，期间每帧无条件 setState → 整页重建

### post-fix2（runId: post-fix2，305 行）

修复 2/3 已生效：

- 顶部越界最深 -100（不再穿透到 -159），且全程 `deg:true, set:false`（封面冻结，纯滚动）。
- 底部不再 overscroll（硬截止生效）。

**但用户仍反馈"严重抖动"（尤其从上向下拉动）**。post-fix2 日志核心异常：

| 段 | 现象 | 证据 |
|----|------|------|
| 中段惯性振荡 | drag:false、out:false 的惯性滚动中 `p` 在 584~670 之间每帧来回跳约 1 秒（预期应为单调摩擦减速） | L226-259：584→610→640→585→622→574→…→606，振幅先增后缓减 |
| 松手瞬间 p 大跳 | 释放首帧位置与拖拽末帧相差数百 px | L266 632→521；L269 156→504；L298 33→379；L35 238→366 |
| 封面状态 | 振荡期间 sh 恒 259.885、set 恒 false | 封面恒定 → 排除"封面高度→viewport→位置反馈"回路 |

| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| G | 惯性期间 ballistic 被反复重启（`BallisticScrollActivity.applyNewDimensions()`→`goBallistic(velocity)`，触发条件：viewport/extent 变化）或 ScrollPosition 被重建（PageStorage 恢复旧 offset） | **待验证** | Low | 单 ListView 单 position，无嵌套滚动体；A 事件 30ms 节流丢失部分轨迹，无法从既有日志判定重启源 |
| H | 列表 extent 因懒加载/图片加载动态变化 → applyContentDimensions 变化 → 惯性重启 | 待验证 | Low | 需 post-fix3 的 max/view/ScrollMetricsNotification 数据 |

## Fix

**变更文件**：`lib/screens/character_detail_screen.dart`

1. **滚动回调**（~L750-800）：由"无条件 setState"改为"**先计算目标状态，封面状态（shrink/dragOffset/expanded/吸附动画）无实际变化时跳过 setState**"；A 类上报新增 `set` 字段用于对比证明。
2. **滚动物理**（新增 `_MomentsScrollPhysics`，~L55-130）：自定义物理，**顶部保留 Bouncing 橡皮筋**（供封面下拉展开），**底部改为 Clamping 硬截止**（到达列表末尾立即停止，不再越界回弹）；向下惯性用 `ClampingScrollSimulation`（到底即停），**向上惯性改官方 `BouncingScrollSimulation`**（摩擦→接近顶部时转入受限弹簧，不再穿透顶部）；顶部越界回弹速度由 `-velocity` 改为原始 `velocity`（与官方 `_underscrollSimulation` 一致，避免收敛振荡）。ListViews 由 `BouncingScrollPhysics` 换为 `_MomentsScrollPhysics`（~L811）。
3. **高复杂度降级**（本轮，用户要求"复杂度过高时朋友圈不加动画滑动"）：滚动回调新增 `degraded` 判定——**松手后的越界回弹（非跟手 dragDetails==null 且 outOfRange）期间跳过封面跟手驱动**，朋友圈只做纯滚动（不加动画），封面在 ScrollEnd 时由 `_settleCover()` 吸附动画一次到位；跟手拖动（下拉展开）与正常范围内惯性滚动仍实时跟随。
4. **post-fix3 插桩**（诊断惯性振荡，待收集日志）：物理类新增 `debug` 回调，记录每次 `createBallisticSimulation`（ballistic，含起点/速度/min/max/序号）与 `applyBoundaryConditions`（boundary，含返回值 r）；A 事件补充 `max`/`view`；新增 `ScrollMetricsNotification`（metrics）监听；A 节流 30ms→8ms；runId=post-fix3。用于判定：惯性是否反复重启（ballistic seq 暴增）、extent 是否变化（max/view/metrics）、position 是否重建（pid）。

> 注：修复 1 的 post-fix 日志已证明底部回弹期 `set:false`（整页零重建），但用户仍反馈"抖动" → 定位到假设 E（顶部惯性穿透）+ F（越界回弹跟手动画）→ 实施修复 2 与 3。post-fix2 证实 2/3 生效，但暴露新的中段惯性振荡 → 启动 post-fix3 插桩。

## Verification Conclusion

[待对比：post-fix3 日志应显示向上惯性不再穿透（`p` 不再跳到 -100 以下深度）、越界回弹期 `deg:true`（封面零跟手）；用户确认"从底部往上滑"不再抖动]
