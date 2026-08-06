# ToolBox 联调与上线问题报告

## 1. 报告范围

- 时间：2026-08-06
- 环境：Windows 11、PowerShell、Python 3.10、Django 4.2、Vue 3、Vite 7、腾讯云 CloudBase
- 范围：本地一键启动、前后端与数据库联调、Django Ninja 试接入、云函数发布、HTTP 网关、静态网站托管、线上浏览器验收
- 生产环境 ID：`da-tool-list-d2g0awsejc0658949`
- 生产云函数：`toolbox-api`
- 生产前端：<https://fe-da-tool-list-d2g0awsejc0658949.webapps.tcloudbase.com/>
- 生产 API：<https://da-tool-list-d2g0awsejc0658949-1464163374.ap-shanghai.app.tcloudbase.com/api>

本文不记录 API Key、Django Secret 等秘密值。

## 2. 最终结果

- 后端 15 项测试通过。
- 前端 TypeScript 检查和 Vite 生产构建通过。
- 云函数为 `Active/Available`。
- 公开 API、前端首页及前端静态资源均返回 HTTP 200。
- 线上页面可以读取 CloudBase，并完成项目的创建、保存和删除。
- 所有联调测试数据均已删除。
- 父仓库和三个子仓库最终均处于干净状态。

## 3. 问题总览

| # | 阶段 | 现象 | 根因 | 处理结果 |
|---|---|---|---|---|
| 1 | VS Code 启动 | F5 后只剩 Vite | 调试器终止父 PowerShell 时，子进程未必进入脚本的 `finally` | 放弃 F5，改用根目录 `npm run dev` |
| 2 | 重复启动 | Vite 报 5173 被占用，Django 随后退出 | 上一次调试留下 Vite；启动脚本发现任一子服务退出后会清理另一服务 | 清理明确 PID；统一由根脚本管理生命周期 |
| 3 | API 日志 | Django 显示多个 `Not Found` | CloudBase 返回集合不存在的 HTTP 404，Django 日志看起来像 URL 未注册 | 查看响应 JSON 后确认数据库错误，而不是只看状态码 |
| 4 | 本地数据库 | `test_*` 三个集合全部不存在 | 根脚本默认添加 `test_` 前缀，但环境未创建测试集合 | 默认改为无前缀生产集合；仍可显式传入测试前缀 |
| 5 | Django Ninja | 旧业务 API 被 Ninja 返回 404 | Ninja URL 被挂在旧业务 URL 之前，未匹配路径不会继续落到旧路由 | 旧业务 `include` 放前面，Ninja 放后面 |
| 6 | 生产打包 | `ninja_api.py` 未进入云函数包 | 生产部署使用文件白名单，新文件未加入清单 | 加入 `deploy/production-files.txt` |
| 7 | 网关部署 | 首次部署在创建函数后报属性不存在 | 严格模式下对空路由集合读取 `UpstreamResourceName` | 先判断路由对象存在，再判断旧路由名称 |
| 8 | 云函数启动 | 网关返回非标准 `443 Unknown` | `scf_bootstrap` 使用不存在的 `python` 命令 | Python 3.10 运行时改用 `python3` |
| 9 | 云函数启动 | 修复入口后仍返回 443，日志报缺少 Django | CloudBase 更新 HTTP 函数时未可靠安装 `requirements.txt` | 构建阶段打包 Linux CPython 3.10 wheels |
| 10 | 静态托管 | `/fe/` 下资源可能访问 `/assets/` | Vite 默认生成根路径绝对资源 URL | Vite 设置 `base: "./"` |
| 11 | 生产联调 | 前端会向自身域名请求 `/api` | `.env.production` 的 API 地址为空，但前后端实际为不同 Origin | 写入正式 API 绝对地址 |
| 12 | 跨域写入 | 前端无法读取 API 域名的 CSRF Cookie | `document.cookie` 只能读取当前 Origin 的 Cookie | `/api/csrf/` 在 JSON 中返回 token，前端缓存并发送请求头 |
| 13 | CORS | GET 响应出现两个相同的允许源 | CloudBase 网关和 Django CORS 中间件同时添加响应头 | 移除 Django CORS 层，交给 CloudBase 网关处理 |
| 14 | 自动化验收 | 页面删除点击超时并停在确认框状态 | 浏览器自动化对原生确认框状态同步不稳定 | 通过 API 精确复核，测试记录实际已删除 |
| 15 | 测试命令 | 一次 Django 测试显示 0 项 | 从父目录以路径调用 `manage.py test`，测试发现目录不正确 | 在 `ToolBoxBackEnd` 工作目录运行，最终发现并执行 15 项 |
| 16 | 输出可读性 | PowerShell 中部分中文显示乱码 | 终端读取 UTF-8 文件时使用了不匹配的代码页/解码方式 | 不影响构建；尚未统一终端编码 |

## 4. 详细问题与处置

### 4.1 F5 调试无法可靠管理两个开发服务

最初在父仓库创建了 VS Code `node-terminal` 启动配置，由它执行 `start-dev.ps1`。脚本本身会启动 Django 和 Vite，并在正常收到中断时执行 `finally` 清理进程树。但停止调试可能直接终止父 PowerShell，导致清理逻辑没有机会完成，出现 Vite 残留。下一次启动时，新 Vite 因端口冲突退出，脚本又会关闭刚启动的 Django，所以用户最终只看到旧 Vite。

最终取消 F5 配置，在父仓库增加 `package.json`：

```powershell
npm run dev
```

该命令仍复用 `start-dev.ps1`。停止服务应在运行它的终端按 `Ctrl+C`。

### 4.2 404 同时可能代表路由错误和数据库错误

`CloudBaseAPIError` 会尽量保留上游状态码。因此 CloudBase 返回 `DATABASE_COLLECTION_NOT_EXIST` 时，Django 同样记录 `Not Found`。这和真正的 Django URL 404 表面相同。

排查时必须同时检查：

1. Django `resolve()` 是否能解析 URL；
2. HTTP 响应 JSON 中的 `error`、`details.code` 和 `request_id`；
3. 当前 `CLOUDBASE_COLLECTION_PREFIX`；
4. CloudBase 中集合是否存在。

本次不存在的集合为：

- `test_work_projects`
- `test_aircraft_templates`
- `test_tool_cart`

根脚本现默认使用无前缀集合。需要隔离测试数据时，必须先创建对应集合，再运行：

```powershell
npm run dev -- -CloudBaseCollectionPrefix test_
```

### 4.3 Django Ninja 路由抢占

Django Ninja 被试接入到 `/api/`，提供 `/api/docs`、`/api/openapi.json` 和两个演示接口。Ninja 的 URLResolver 对未匹配的 `/api/*` 请求直接形成 404，因此不能放在旧业务 URL 之前。

正确顺序：

```python
urlpatterns = [
    path("", include("api.urls")),
    path("api/", ninja_api.urls),
]
```

当前 Swagger 只描述 Ninja 演示接口，不包含旧函数式业务 API。这是试接入，不是完整迁移。

### 4.4 生产包白名单遗漏新模块

部署脚本只从 Git `main` 的 `deploy/production-files.txt` 打包。`cloudrun/urls.py` 引用了 `api.ninja_api`，但新文件最初不在白名单中，部署后会在 import 阶段失败。

已把 `api/ninja_api.py` 加入白名单。今后新增任何生产 import，都必须同步检查白名单，可考虑新增自动化测试验证递归 import 依赖是否完整。

### 4.5 网关空路由严格模式错误

第一次部署成功创建了 `toolbox-api`，但环境中还没有 `/api` 路由。脚本在 PowerShell StrictMode 下直接访问空对象属性，部署在路由创建之前中断。

已增加 `[bool]$pathRoute` 短路判断。需要注意：部署过程不是事务，失败时可能出现“函数已创建但路由未创建”或“路由已创建但冒烟测试未通过”的中间状态。重试前应查询函数和路由现状，而不是假设全部回滚。

### 4.6 云函数运行时入口名错误

CloudBase Python 3.10 HTTP 函数中不存在 `python`，实际可用命令为 `python3`。错误表现为：

```text
./scf_bootstrap: line 2: exec: python: not found
```

已改为：

```bash
exec python3 manage.py runserver 0.0.0.0:9000 --noreload --settings=cloudrun.settings_scf
```

网关的 `443 Unknown` 不是 HTTPS 443 端口错误，而是 CloudBase 用来表示上游函数启动失败的非标准状态码。必须结合 `x-cloudbase-request-id` 查询函数日志。

### 4.7 Python 依赖没有被云端更新器安装

函数更新后日志显示：

```text
ModuleNotFoundError: No module named 'django'
```

虽然 CloudBase MCP 的更新操作设置了依赖安装标记，HTTP 函数更新流程没有可靠安装 Python `requirements.txt`。部署脚本现使用本地 pip 在临时生产目录中下载目标运行时依赖：

- 平台：`manylinux2014_x86_64`
- 实现：CPython
- Python：3.10
- ABI：`cp310`
- 只接受 wheel，避免在 Windows 构建 Linux 扩展

这保证 `pydantic-core` 等二进制包使用 Linux wheel，而不是误打包 Windows `.pyd`。

### 4.8 静态托管子路径与 API Origin

现有静态托管将独立域名根路径重写到存储的 `/fe` 前缀。Vite 默认生成 `/assets/...`，无法正确加载 `/fe/assets/...`。设置 `base: "./"` 后，HTML 使用 `./assets/...`，兼容两个访问地址：

- 推荐：<https://fe-da-tool-list-d2g0awsejc0658949.webapps.tcloudbase.com/>
- 原始静态域名：<https://da-tool-list-d2g0awsejc0658949-1464163374.tcloudbaseapp.com/fe/>

前端与 API 为不同 Origin，因此生产构建显式设置 API 根地址。CloudBase 网关负责 CORS 和 OPTIONS 预检；Django 只维护 `CSRF_TRUSTED_ORIGINS`。

### 4.9 跨 Origin CSRF

原前端只从 `document.cookie` 读取 `csrftoken`。跨 Origin 时，API Cookie 不属于前端 Origin，JavaScript 无法读取。

现在 `/api/csrf/` 返回：

```json
{
  "ok": true,
  "csrf_token": "..."
}
```

前端把 token 保存在内存中，写请求通过 `X-CSRFToken` 发送，同时保留 `credentials: "include"`。Django 的 CSRF Cookie 不暴露给其他域名的 JavaScript。

### 4.10 重复 CORS 响应头

CloudBase HTTP 网关会根据 Origin 自动添加 CORS 响应头。曾同时启用 `django-cors-headers`，导致响应为两个相同的 `Access-Control-Allow-Origin` 值。多个允许源值不符合浏览器要求。

最终方案：

- CloudBase 网关：CORS、OPTIONS；
- Django：CSRF Origin 校验；
- 不在 Django 中再次添加 CORS 响应头。

### 4.11 自动化删除确认框超时

线上 UI 删除操作触发浏览器原生 `confirm()`。自动化工具在点击与对话框状态切换之间发生超时，但数据库复核显示记录已经删除。最终又通过精确测试名称查询，确认剩余记录为 0。

这属于验收工具同步问题，不是生产删除接口失败。后续端到端测试可把原生 `confirm()` 替换为应用内对话框，提升可测试性。

### 4.12 中文终端乱码

PowerShell 读取部分 UTF-8 源文件时显示乱码，但浏览器页面中文正常，构建也正常。这说明主要问题是终端解码而非文件内容。

建议后续统一：

```powershell
[Console]::InputEncoding = [Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$OutputEncoding = [Text.UTF8Encoding]::new()
```

同时检查 Git `working-tree-encoding`、编辑器保存编码和 CI 终端代码页。

## 5. 尚存风险与建议

### 5.1 API 当前无用户认证

公开 `/api` 网关未启用网关鉴权，Django 业务 API 也没有用户级认证。任何知道地址的访问者理论上可以读写项目、模板和工具车。CSRF 不能代替身份认证。

建议上线真实业务数据前增加：

- CloudBase 登录态或企业身份认证；
- Django 用户/Token 校验；
- 按团队或用户限制文档访问；
- 写接口审计日志和速率限制。

### 5.2 CloudBase 请求延迟

联调中单次 CloudBase 请求常见约 4～5 秒，页面完整保存可能达到 10～15 秒。当前前端用“正在保存”状态掩盖延迟，但没有请求合并、重试退避或后台任务。

建议：

- 复用 HTTP 连接，避免每次 `urllib` 新建连接；
- 批量写入或合并连续编辑；
- 对只读模板与工具车加短时缓存；
- 为慢请求记录 CloudBase request ID 和耗时；
- 评估 CloudBase SDK、CloudRun 常驻服务或同地域私网访问。

### 5.3 部署不是原子操作

函数、配置、代码、网关路由和静态文件是多个独立步骤。脚本失败不会自动恢复到旧版本。建议后续增加：

- 部署前记录旧函数版本与路由；
- 冒烟失败时自动恢复旧代码或路由；
- 前端上传使用版本目录，验证后再切换入口；
- CI/CD 中串行执行 dry-run、测试、部署、冒烟和回滚。

### 5.4 旧静态哈希文件未清理

本次上传覆盖了新 `index.html` 并增加新哈希资源，没有删除旧哈希资源。它们不会被新页面引用，但会占用少量存储。清理时应只删除确认不再被任何 HTML 引用的旧文件，避免先删后传造成短时不可用。

### 5.5 本地测试集合文档存在漂移

父仓库原 README 仍描述“默认使用 `test_*` 集合”，而当前 `start-dev.ps1` 默认前缀已经改为空。实际行为以脚本为准。建议后续统一 README，并明确“本地直连正式集合”的数据风险。

## 6. 推荐验收清单

每次发布至少执行：

```powershell
# 后端
cd ToolBoxBackEnd
.\.venv\Scripts\python.exe manage.py test
.\scripts\deploy-production.ps1
.\scripts\deploy-production.ps1 -Deploy

# 前端
cd ..\ToolBoxWebFrontEnd
npm run check
```

线上验证：

1. 前端首页和当前哈希资源返回 200；
2. `/api/cloudbase/status/` 返回 `configured: true`；
3. `/api/projects/?limit=1` 返回 `ok: true`；
4. 使用正式前端 Origin 验证 CORS GET 和 OPTIONS；
5. 从页面创建唯一名称的临时项目；
6. 确认“数据已保存”；
7. 删除临时项目并通过 API 确认剩余 0 条；
8. 检查浏览器控制台和云函数日志；
9. 检查所有 Git 仓库均为干净状态。
