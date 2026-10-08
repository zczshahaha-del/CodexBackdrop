# CodexBackdrop 项目规则

本项目属于个人项目，仓库为 `zczshahaha-del/CodexBackdrop`。不使用公司评审服务、公司群或公司专用规则。

- 继续开发前读取适用的 `zc-dev-workflow`；修改代码同时遵循 `steady-code-change`。
- 重要改动先建立 GitHub Issue，再创建开发分支。Bug 的现象、环境、复现、排查、原因、修复、验证和未完成验收以 Issue 为主记录。
- `docs/troubleshooting/` 只保存可复用的排障方法，并链接原 Issue；本地文档不能代替 GitHub 问题记录。
- 完成一段完整改动后提交。已授权同步 GitHub 时推送开发分支并建立关联 PR；只有用户明确确认后才合并到 `main`。
- 验收未完成时保持 Issue 开放、PR 草稿状态；说明实际验证与未验证部分，不把辅助功能赋值当作鼠标拖动验收。
- 保留既有修改、用户媒体和设置。截图、配置、日志、构建产物和备份留在被忽略的 `build/` 或 `dist/`，不上传。
- 修改后按风险运行 `bash scripts/check.sh`、`bash scripts/test-menu.sh` 和 `bash scripts/build.sh`。实际窗口测试会暂时切换背景，运行条件与恢复要求见 README。
- 重启 Codex 前取得用户确认；修复助手不意味着可以中断其他聊天。
