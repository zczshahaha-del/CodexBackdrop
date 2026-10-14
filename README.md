# CodexBackdrop

给 macOS Codex 桌面应用添加动态背景、照片或视频的本地菜单栏助手。应用中仍显示为「Codex 动态背景」，当前版本为 3.5.3。

这是个人开发的非官方增强，不修改 Codex 的安装文件，也不上传背景文件。Codex 更新后可能需要修复连接或重新适配界面。

## 功能

- 4 种轻量动态背景：流动渐变、极光、柔光光斑、流星雨。
- 原有宇宙星河和动态粒子效果。
- 本地照片与循环视频背景，支持 HEIC/HEIF 照片转换。
- 菜单栏切换背景、调整可见度，支持「背景始终清晰」。
- 保存选择与透明度；连接可用时自动恢复丢失的背景。

## 构建

需要 macOS 13 或更新版本、Xcode Command Line Tools，以及 Node.js 22 或更新版本。脚本优先使用已安装 Codex 内置的 Node，也可通过 `NODE_BIN` 指定。

```sh
bash scripts/build.sh
```

产物位于 `dist/`：Apple Silicon + Intel 通用 `.app` 和对应 ZIP。`build/`、`dist/` 均不提交到 Git。

```sh
open "dist/Codex 动态背景.app"
```

点击菜单栏星光图标选择背景。背景连接已开启时直接应用；Codex 正在运行但没有连接时，先保存选择，等待连接恢复，不会退出或重启 Codex。完成当前工作并自行退出 Codex 后，可从助手菜单选择「打开 Codex（启用背景连接）」正常启动并应用背景。Codex 未运行时，选择背景也会正常打开它。

完整操作见 [使用说明](docs/使用说明.txt)。当前构建只进行本地 ad-hoc 签名，未做 Apple 公证；不是 App Store 安装包。

## 检查

```sh
bash scripts/check.sh
```

原生菜单、透明度更新与连接等待的回归检查不会连接 Codex，也不会改变用户设置：

```sh
bash scripts/test-menu.sh
```

当 Codex 正在运行且 9224 背景连接未开启时，可验证实际应用路径不会退出或重新打开它。此项使用临时独立设置并自动清理，保留用户原设置：

```sh
"dist/Codex 动态背景.app/Contents/MacOS/CodexDynamicBackground" --no-restart-smoke-test
```

连接实际 Codex 窗口的测试会临时切换背景，不会重启 Codex。先从菜单选择一个内置效果，并确保背景连接已开启：

```sh
NODE_BIN="/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
mkdir -p build/qa
"$NODE_BIN" tests/test-light-effects.mjs 9224 build/qa
```

截图保存在被 Git 忽略的 `build/qa/`，可能包含聊天内容，请勿上传。测试完成后恢复原内置效果和透明度。

可选 `--restore` 会测试菜单栏助手的自动恢复，要求助手正在运行且其保存的模式、透明度与测试前页面一致：

```sh
"$NODE_BIN" tests/test-light-effects.mjs 9224 build/qa --restore
```

不保证 Intel 实机表现；目前只验证了双架构编译，实际功能测试在 Apple Silicon Mac 上完成。

## 安全边界

- 通过本机 `127.0.0.1:9224` 的远程调试连接加载背景，不需要账号令牌或 API Key。
- 该调试连接也能访问 Codex 页面；只在可信电脑上使用，不要将端口代理到外网。
- 「关闭动态背景」只移除效果，不会关闭调试端口。需要关闭端口时退出 Codex，再普通启动。
- 媒体、用户设置、截图、聊天记录和签名证书不应提交到仓库。

## 项目结构

- `src/`：Swift 菜单栏助手、背景渲染器与应用信息。
- `assets/`：本项目生成的应用图标，不含用户媒体。
- `scripts/`：可重复的检查和打包命令。
- `tests/`：实际窗口集成测试。
- `tools/`：图标生成器与本地诊断脚本。
- `docs/`：需求、架构、使用说明和排障记录。

项目尚未选择开源许可证。

## 开发与问题记录

按 [项目规则](AGENTS.md) 使用 GitHub Issue、开发分支、Commit 和 PR。Bug 的完整记录放在 Issue，本地排障文档链接对应问题；验收未完成时保持 Issue 开放，合并需用户明确确认。
