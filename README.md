# wk-cfnew-auto-update

## 🚀 快速开始（适合 Fork）

### 前置条件

- 一个 GitHub 账号
- 一个 Cloudflare 账号（需具备 Workers 和 KV 管理权限）

### 部署步骤

1. **Fork 本仓库**：点击页面右上角 **Fork** 按钮，将仓库复制到你的 GitHub 账号。

2. **启用 GitHub Actions**：进入你 Fork 后的仓库，点击 **Actions** 页面，首次访问会提示启用 workflows。

3. **配置 Cloudflare 凭证（Secrets）**：在仓库页面依次点击 **Settings → Secrets and variables → Actions → New repository secret**，添加以下敏感信息：

   | 类型    | 名称              | 说明                                                                                        | 必填 |
   | ------- | ----------------- | ------------------------------------------------------------------------------------------- | ---- |
   | Secrets | `CF_API_TOKEN`    | Cloudflare API Token，需包含 `Workers:Edit`、`Workers Routes:Edit`、`Workers KV:Write` 权限 | 是   |
   | Secrets | `CF_ACCOUNT_ID`   | Cloudflare 账户 ID，可在 Cloudflare Dashboard URL 中获取                                    | 是   |
   | Secrets | `CF_VAR_U`        | 环境变量 u 的值（UUID），用于更新 Worker 配置                                               | 否   |
   | Secrets | `CF_ROUTE_DOMAIN` | 自定义域名（如 `shop.example.com`），配置后自动启用自定义路由                               | 否   |

4. **触发更新**：完成配置后，你可以：
   - **手动触发**：进入 **Actions** 页面，选择 "auto update and deploy" 工作流，点击 **Run workflow** 手动执行。
   - **等待自动执行**：工作流会于每天 **UTC 16:00（北京时间 00:00）** 自动检查并执行更新。

> **重要提示**：确保你的仓库默认分支为 `main`，否则推送时可能失败。

🌟 如果觉得这个项目对你有帮助，欢迎顺手点个 Star 支持一下！

## 功能介绍

本项目实现对 [byJoey/cfnew](https://github.com/byJoey/cfnew) 仓库的自动同步与部署，主要功能如下：

### 核心功能

| 功能                | 说明                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| **自动版本检测**    | 每日定时（UTC 16:00）检查上游仓库最新 Release 版本                         |
| **自动下载部署**    | 检测到新版本后，自动下载 `Pages.zip` 并提取 `_worker.js`                   |
| **KV 命名空间管理** | 自动创建 Cloudflare KV 命名空间或复用已有命名空间，并绑定到 Worker         |
| **自定义域名**      | 支持通过 `CF_ROUTE_DOMAIN` 配置自定义域名，自动设置路由规则                |
| **环境变量配置**    | 支持通过 `CF_VAR_U` 动态更新 Worker 环境变量（UUID）                       |
| **自动提交推送**    | 更新完成后自动提交代码变更并推送到 `main` 分支                             |
| **更新通知**        | 自动复用或创建带有 `auto-update-status-issue` 标签的 GitHub Issue 进行通知 |

### 版本控制机制

- **版本记录文件** `version.txt`：存储当前已部署的版本号
- **版本比较**：读取本地 `version.txt` 与最新版本号对比

## 工作流程

### 触发条件

| 触发方式     | 说明                                                                          |
| ------------ | ----------------------------------------------------------------------------- |
| **定时触发** | 每天 UTC 16:00（北京时间 00:00）自动执行                                      |
| **手动触发** | 在 GitHub Actions 页面选择 "auto update and deploy" 工作流，点击 Run workflow |

### 执行步骤

完整工作流程包含以下步骤：

#### 阶段一：版本检测与代码更新

| 步骤             | 说明                                                                           |
| ---------------- | ------------------------------------------------------------------------------ |
| 1. Checkout 仓库 | 检出仓库代码                                                                   |
| 2. 设置 Node.js  | 配置 Node.js 最新稳定版                                                        |
| 3. 安装依赖      | 安装 jq、curl、unzip 工具                                                      |
| 4. 获取最新版本  | 调用 GitHub API 获取上游仓库最新 Release 版本号                                |
| 5. 读取当前版本  | 读取本地 `version.txt` 内容                                                    |
| 6. 判断是否更新  | 比较版本号，确定是否需要更新                                                   |
| 7. 下载并提取    | 若版本不一致，下载 `Pages.zip` 并解压提取 `_worker.js`，同时更新 `version.txt` |
| 8. 提交推送      | 将更新后的 `_worker.js` 和 `version.txt` 提交并推送到 `main` 分支              |

#### 阶段二：更新通知

| 步骤        | 说明                                                                               |
| ----------- | ---------------------------------------------------------------------------------- |
| 9. 发送通知 | 查找带有 `auto-update-status-issue` 标签的 Issue，找到则添加评论，否则创建新 Issue |

#### 阶段三：Cloudflare 部署配置

| 步骤                | 说明                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------ |
| 10. 初始化环境      | 安装项目依赖（wrangler）                                                             |
| 11. KV 命名空间处理 | 执行 `scripts/step-kv.sh` 创建新 KV 或复用已有 KV，并更新 `wrangler.toml` 中的 KV ID |
| 12. 更新环境变量    | 若 `CF_VAR_U` 已配置，更新 `wrangler.toml` 中的 `u` 变量                             |
| 13. 配置自定义域名  | 若 `CF_ROUTE_DOMAIN` 已配置，自动添加 `[[routes]]` 配置并设置 `workers_dev = false`  |
| 14. 部署 Worker     | 执行 `npm run deploy` 部署到 Cloudflare Workers                                      |

### 版本一致处理

若检测到本地版本与上游最新版本一致（`need_update=false`），工作流会**跳过以下步骤**，直接结束：

| 跳过的步骤 | 说明                                                                    |
| ---------- | ----------------------------------------------------------------------- |
| 7-14       | 下载提取、提交推送、通知、初始化环境、KV 处理、环境变量、域名配置、部署 |

## 📂 目录结构

```text
wk-cfnew-auto-update/
├── _worker.js                 # Cloudflare Worker 主文件（上游同步）
├── version.txt                # 当前已部署版本记录
├── wrangler.toml             # Cloudflare Workers 配置文件
├── package.json              # 项目依赖配置
├── .gitignore                # Git 忽略规则
├── .gitattributes            # Git 属性配置（行尾符、脚本类型）
├── scripts/                  # 自动化脚本目录
│   ├── step-kv.sh           # KV 命名空间创建/绑定脚本 (Linux/macOS)
│   ├── step-kv.ps1          # KV 命名空间创建/绑定脚本 (Windows)
│   └── backups/              # 配置文件备份目录
└── .github/
    └── workflows/
        └── update_worker.yml # GitHub Actions CI/CD 工作流
```

### 技术栈概览

| 类别         | 技术               | 版本   | 说明                   |
| ------------ | ------------------ | ------ | ---------------------- |
| **运行时**   | Cloudflare Workers | -      | Edge computing 平台    |
| **部署工具** | Wrangler           | ^4.0.0 | Cloudflare Workers CLI |
| **CI/CD**    | GitHub Actions     | -      | 自动化工作流引擎       |
| **脚本语言** | Bash / PowerShell  | -      | KV 自动化脚本          |
| **依赖管理** | npm                | -      | Node.js 包管理器       |
| **上游仓库** | byJoey/cfnew       | -      | Worker 源码来源        |

## ⚙️ 配置说明

### 1. GitHub Secrets（敏感信息）

在仓库 **Settings → Secrets and variables → Actions** 中配置以下 Secrets：

| 名称              | 必填 | 说明                                                                                                  |
| ----------------- | ---- | ----------------------------------------------------------------------------------------------------- |
| `CF_API_TOKEN`    | 是   | Cloudflare API Token，需包含 `Workers:Edit`、`Workers Routes:Edit`、`Workers KV:Write` 权限           |
| `CF_ACCOUNT_ID`   | 是   | Cloudflare 账户 ID，可在 Dashboard URL 中获取（格式：`https://dash.cloudflare.com/<ACCOUNT_ID>/...`） |
| `CF_VAR_U`        | 否   | 环境变量 `u` 的值（UUID），用于更新 `wrangler.toml` 中的 `[vars]` 配置                                |
| `CF_ROUTE_DOMAIN` | 否   | 自定义域名（如 `shop.example.com`），配置后自动设置 `workers_dev=false` 并添加 `[[routes]]`           |

### 2. 工作流环境变量

工作流使用 `env` 环境变量进行配置，所有变量定义在 job 级别：

| 变量名         | 必填 | 默认值         | 说明                                                     |
| -------------- | ---- | -------------- | -------------------------------------------------------- |
| `GITHUB_REPO`  | 是   | `byJoey/cfnew` | 上游仓库，格式：`owner/repo`                             |
| `RELEASE_TYPE` | 否   | `release`      | 更新类型：`release`（正式版）或 `prerelease`（预发布版） |
| `KV_NAME`      | 否   | `cf-new-kv`    | Cloudflare KV 命名空间名称                               |

#### 环境变量配置示例

```yaml
jobs:
  update:
    runs-on: ubuntu-latest
    env:
      GITHUB_REPO: byJoey/cfnew # 上游仓库
      RELEASE_TYPE: release # 更新类型：release 或 prerelease
      KV_NAME: cf-new-kv # KV 命名空间名称
```

> **说明**：修改工作流中的环境变量需要直接编辑 `.github/workflows/update_worker.yml` 文件。

#### 配置方式说明

| 配置方式           | 说明                                                                      |
| ------------------ | ------------------------------------------------------------------------- |
| **GitHub Secrets** | 用于敏感信息（API Token、账户 ID 等），在仓库 Settings 中配置             |
| **env 环境变量**   | 用于工作流内部配置（上流仓库、更新类型、KV 名称），在 workflow 文件中定义 |

#### 迁移说明

工作流采用 `env` 环境变量进行内部配置，不使用 `workflow_dispatch.inputs` 方式。

如需自定义 `RELEASE_TYPE` 或 `KV_NAME`，请编辑 `.github/workflows/update_worker.yml` 文件中的 `env` 区块。

### 3. wrangler.toml 配置说明

项目根目录下的 `wrangler.toml` 是 Cloudflare Workers 的核心配置文件：

| 配置项                      | 类型    | 说明                                      |
| --------------------------- | ------- | ----------------------------------------- |
| `name`                      | string  | Worker 名称                               |
| `main`                      | string  | 入口文件路径                              |
| `compatibility_date`        | string  | 兼容性日期，指定 Worker 运行时版本        |
| `no_bundle`                 | boolean | 是否禁用打包（`true` 表示直接上传单文件） |
| `workers_dev`               | boolean | 是否启用 `workers.dev` 子域名             |
| `preview_urls`              | boolean | 是否启用预览 URL                          |
| `[vars]`                    | object  | 环境变量，如 `u`（UUID 值）               |
| `[[kv_namespaces]]`         | array   | KV 命名空间绑定列表                       |
| `[[kv_namespaces]].binding` | string  | 代码中引用的名称                          |
| `[[kv_namespaces]].id`      | string  | 实际 KV 命名空间 ID（首次运行后自动更新） |
| `[observability]`           | object  | 可观测性配置                              |
| `[observability.logs]`      | object  | 日志配置                                  |
| `[observability.traces]`    | object  | 调用追踪配置                              |

> **说明**：`wrangler.toml` 中的 KV 命名空间 ID 会在工作流首次运行时自动创建并更新，无需手动配置。

### 4. 更新通知机制

工作流通过 GitHub Issue 进行更新通知：

| 组件       | 说明                                                 |
| ---------- | ---------------------------------------------------- |
| Issue 标题 | `_worker.js 自动更新通知`                            |
| 标签       | `auto-update`、`success`、`auto-update-status-issue` |
| 通知方式   | 复用已有 Issue 并添加评论，或创建新 Issue            |
| 评论内容   | 更新时间、版本号                                     |

> **提示**：关注带有 `auto-update-status-issue` 标签的 Issue 即可接收所有更新通知。

### 5. 本地开发

```bash
# 安装依赖（需 Node.js >= 18）
npm install

# 本地开发调试
npm run dev

# 部署到 Cloudflare（需提前配置 wrangler）
npm run deploy
```

> **前提条件**：本地开发前需配置 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID` 环境变量，或通过 `npx wrangler login` 进行认证。

## 📜 开源协议

本项目基于 **MIT License** 开源。

**你有权**：

- 免费使用、复制、修改本项目代码
- 分发本项目的衍生作品
- 将本项目用于商业或非商业目的

**你必须**：

- 在衍生作品中附带原始许可证声明
- 在代码中保留版权声明

**你不得**：

- 使用本项目名称进行商业推广或误导性声明

详细许可证内容请参阅项目根目录 LICENSE 文件（如有）。

## ⚠️ 免责声明

1. **使用目的**：本项目（`wk-cfnew-auto-update`）仅供**教育、科学研究及个人安全测试**之目的。

2. **合规使用**：使用者在下载或使用本项目代码时，必须严格遵守所在地区的法律法规。

3. **无责任声明**：作者 **glacier92xr** 对任何滥用本项目代码导致的行为或后果均不承担任何责任。

4. **无担保**：本项目不对因使用代码引起的任何直接或间接损害负责。

5. **临时使用建议**：建议在测试完成后 **24 小时内** 删除本项目相关部署。

## 📢 特别说明

| 项目         | 说明                                                                 |
| ------------ | -------------------------------------------------------------------- |
| **上游来源** | 本仓库同步内容来源于 [byJoey/cfnew](https://github.com/byJoey/cfnew) |
| **版权归属** | 原项目版权归原作者所有                                               |
| **项目目的** | 本项目仅用于自动同步更新，不对原内容进行修改                         |

## 🛠 代码引用

本项目参考了以下开源项目：

| 项目                                                              | 说明                               |
| ----------------------------------------------------------------- | ---------------------------------- |
| [byJoey/wk-Auto-update](https://github.com/byJoey/wk-Auto-update) | Cloudflare Worker 自动更新机制参考 |

## Star History

![Star History Chart](https://api.star-history.com/svg?repos=glacier92xr/wk-cfnew-auto-update&type=Timeline)
