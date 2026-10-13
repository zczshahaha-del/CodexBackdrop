# 运行中背景合成实验

关联 [Issue #5](https://github.com/zczshahaha-del/CodexBackdrop/issues/5)。这是独立模拟窗口，不是 Codex 主窗口接入实现，也不进入正式应用构建。

原型创建自己的 AppKit 窗口，用 `NSView.cacheDisplay` 读取自己绘制的控件，替换指定底色后显示在不接收鼠标的子窗口中。计数按钮仍属于原窗口。它没有 ScreenCaptureKit、跨应用辅助功能调用、网络访问或 Codex 连接。

```sh
mkdir -p build/qa/window-compositor
xcrun swiftc -module-cache-path build/module-cache-tests \
  tools/experimental/window-compositor/BackgroundCompositor.swift \
  tools/experimental/window-compositor/LiveDemo.swift \
  -o build/qa/window-compositor/live-demo
build/qa/window-compositor/live-demo
```

运行会打开一个明确标为模拟的窗口；关闭它会结束原型。点击计数按钮、改变窗口大小可观察原窗口事件与合成画面。构建和启动真实 AppKit 窗口需要正常的图形会话，受限沙盒可能无法绘制 Core Image 图像。

## 已验证与限制

- 在独立原型窗口中，用鼠标坐标点击，显示计数从 0 到 1；放大窗口后再次点击，显示计数从 1 到 2。合成层跟随缩放，模拟图片中的黑色未被替换。
- 控件和图片保护区域由原型自己提供，不能代表真实 Codex 中已能自动识别。文字和控件附近保留原底色，会出现深色矩形；这是保证模拟内容不被改动的实验取舍，尚不符合成品视觉要求。
- 运行输出出现多次按钮动作日志，与两次 UI 验证的计数不一致；其原因尚未确认，不能据此宣称点击行为稳定或性能达标。
- 当前使用已弃用的 Core Image kernel 源码接口，仅用于研究；发布前需要替换为受支持实现。
- 未验证真实 Codex 窗口读取、图片区域识别、前后台遮挡、多显示器、滚动和输入延迟，也没有请求或变更任何系统权限。

如果继续真实接入，需要先明确用户是否接受实时窗口合成这种方式及其新增的录屏、辅助功能权限。实现应只读取选定 Codex 窗口，在本机内存处理，不保存画面或文本，也不上传；任何保护区域识别或定位失败时应隐藏合成层。窗口内容不得回传给自动化工具来规避受限应用的访问限制。
