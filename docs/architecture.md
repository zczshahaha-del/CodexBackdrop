# 实现结构

`MenuBarApp.swift` 使用 AppKit 提供菜单栏入口，保存背景模式、文件路径、透明度与清晰模式。应用发现当前 Codex 安装路径，调用其内置 Node 执行 `helper.mjs`。

`helper.mjs` 连接本机 9224 端口的主窗口，通过 Chrome DevTools Protocol 在页面中创建背景和样式。媒体只在本机读取并加载到页面内存；页面重新加载后，由菜单栏助手重新应用。

四种轻量效果使用固定渐变、静态 SVG 星点以及 transform/opacity 动画；旧宇宙和粒子效果使用 Canvas。所有效果均位于页面内容后方。

切换背景时移除旧节点、动画、可见性监听器和媒体 Object URL。关闭背景还原原主题；退出菜单栏助手不会退出 Codex。

项目文件位置不参与用户设置的标识。应用继续使用现有 bundle identifier，因此整理仓库不改变已安装助手的设置。
