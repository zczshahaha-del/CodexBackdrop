# 新建对话输入框出现方形黑底

原问题与实际验收：[Issue #8](https://github.com/zczshahaha-del/CodexBackdrop/issues/8)。

Codex 的 home 输入布局在内层 `_ComposerLayoutBody_` 绘制圆角面板，外层 `_ComposerLayoutRoot_` 只负责布局。给外层统一加背景或模糊，会让矩形底色露在内层圆角之外；内层原生不透明底色又会挡住背景。

排查时区分布局容器和实际绘制层，检查 `data-composer-utility-bar-variant`。home 外层保持透明，通过其 `--composer-layout-surface-background` 和 `--composer-layout-surface-backdrop-filter` 让内层继续沿用原生绘制、圆角与布局；非 home 布局保留原规则。不通过移动、裁切容器或反复重建背景掩盖底色问题。

`bash scripts/test-composer.sh` 使用离线 WebKit 页面，覆盖 home/已有对话切换、新建节点、透明度与清晰模式、原几何和侧栏装饰。它不代表真实 Codex 页面视觉验收，实际结果继续记录在 Issue。
