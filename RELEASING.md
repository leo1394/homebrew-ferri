# 发布 Ferri

Ferri 使用统一发布器的 **go-binary** 策略：根目录 `main.go`、`go.mod`、`scripts/release/main.go` 和预编译二进制 Formula。开发生成的 `bin/ferri` 不会被当作单文件脚本项目。

## 准备和发布

使用 Go **1.26.5**（与 Release CI 一致），在 Homebrew 工作区执行：

```sh
# 只预览，不改文件、不联网
bash ~/TARS/Homebrew/publish.sh --target homebrew-ferri --dry-run

# 更新版本、发布日期、测试预期和真实二进制校验值，执行检查
bash ~/TARS/Homebrew/publish.sh --target homebrew-ferri --version 0.1.0 --prepare --bottle

# 审核准备结果，提交源码与 Formula，并先推送 master；不提交 bin/、dist/ 或 bottle-output/
# 随后正式发布：
bash ~/TARS/Homebrew/publish.sh --target homebrew-ferri --apply --bottle
```

`--apply` 要求：已配置 origin 与 Git 身份、master 工作区干净、HEAD 与 origin/master 同步、目标 tag 尚不存在、gh 已登录。发布器创建 annotated tag 并推送，随后对该 tag 调用 `release.yml` 的 `workflow_dispatch`，等待流程结束。**仅推送 tag 不再自动发布。** Workflow 文件必须先存在于仓库默认分支，才可通过 API 调度。

发布器的实现位于 `~/Scripts/libs/publish-strategy-go-binary.sh`，由 `publish.sh` 加载。安装脚本通过 Bash 语法与 ShellCheck 检查，保留项目现有格式；Formula 通过 `brew style` 检查。准备阶段会构建五种平台程序；正式发布前在临时副本重建并比对 Formula，防止旧校验值或编译器版本不一致。

## 发布产物和客户端安装

- 独立二进制：macOS ARM64 / Intel、Linux ARM64 / Intel、Windows x64，以及 SHA256SUMS 和第三方许可证声明。
- 加 `--bottle`：CI 在 macOS 15 ARM64 / Intel 上将已发布二进制打包为 Bottle，测试安装、补全及版本，验证 SHA256 后上传至同一 GitHub Release。
- Bottle 发布完成后，CI 只向 master 提交 `Formula/ferri.rb` 的 `bottle do` 更新。仓库需允许 GitHub Actions 的 `contents: write` token 推送 master；分支保护阻止写入时流程会失败，不会报告成功。工作区仅通过 fast-forward 拉回结果，不覆盖用户改动。
- 客户端运行 `brew install leo1394/ferri/ferri`，匹配 Bottle 时直接安装 Bottle；没有匹配 Bottle 时，Formula 仍下载对应平台的预编译程序，**不会本地编译**。只有显式 `--HEAD` 才使用 Go 编译。
- 不加 `--bottle` 仅发布独立二进制，保留同样的客户端免编译安装能力。此策略不使用 go-source 的 Formula PR / test-bot / pr-pull 或 `--formula-hotfix`。

## 失败恢复

发布器不移动已存在的 tag，不覆盖同名 Release 文件。上传重试时，同名文件内容必须完全一致；有差异立即停止。Workflow 失败后，检查输出中的 run ID，并在 GitHub Actions 重跑失败任务；不要删除 tag 重发，也不要使用 `--clobber`。若 tag 已推送但 workflow 调度失败，可手动针对该 tag 调度 Release workflow，并选择是否生成 bottles。

Bottle 汇总要求两个架构均成功，校验平台、版本、文件名、可重定位属性与实际 SHA256。更新 master 前还会确认源码未发生其他变化，避免把旧版本 Bottle 写入新版本 Formula。设备工具的下载仍由用户在首次安装应用时确认；发布流程不向连接的手机安装应用。

本地验证：`go test ./...`、`go vet ./...`、`bash tests/completion_test.sh`、`ruby tests/bottle_metadata_test.rb`；Windows 构建后运行 `./tests/windows_test.ps1`。通用发布器测试为工作区的 `tests/publish_test.sh` 和 `tests/publish_go_binary_test.sh`。

Ferri 内置 Android binary XML 与 Apple plist 解析库，无新增运行时工具要求，许可证见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。这是第三方 tap，不表示已进入 Homebrew core。
