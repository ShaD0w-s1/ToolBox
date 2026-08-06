# ToolBox

ToolBox 是一个前后端分离的工具清单应用。父仓库通过 Git 子模块管理 Django 后端与 Vite 前端，并提供统一的本地开发启动脚本。

## 仓库结构

```text
ToolBox/
├── ToolBoxBackEnd/   # Django HTTP API
├── ToolBoxFrontEnd/  # Vite 前端
└── start-dev.ps1     # 同时启动前后端开发服务器
```

业务数据存储在腾讯云 CloudBase NoSQL 中。Django 的本地 SQLite 仅用于框架自身的会话、认证和迁移，不存储项目、模板或工具车等业务数据。

## 首次初始化

克隆父仓库后初始化子模块：

```powershell
git submodule update --init --recursive
```

初始化后端：

```powershell
cd ToolBoxBackEnd
py -3.10 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe manage.py migrate
cd ..
```

在 `ToolBoxBackEnd/.env` 中填写有效的 `CLOUDBASE_ENV_ID` 和服务端 `CLOUDBASE_API_KEY`。不要提交 `.env` 或任何密钥。

初始化前端：

```powershell
cd ToolBoxFrontEnd
npm install
cd ..
```

## CloudBase 测试集合

本地开发默认使用以下独立集合，避免污染正式数据：

- `test_work_projects`
- `test_aircraft_templates`
- `test_tool_cart`

请在 CloudBase 环境中一次性创建这些集合。正式环境不设置 `CLOUDBASE_COLLECTION_PREFIX`，继续使用无前缀的正式集合。

如需为不同开发者使用独立集合，可以在启动时指定其他前缀：

```powershell
.\start-dev.ps1 -CloudBaseCollectionPrefix dev_zhang_
```

## 本地开发

在父仓库根目录运行：

```powershell
.\start-dev.ps1
```

脚本会同时启动：

- 前端：<http://localhost:5173/>
- 后端：<http://127.0.0.1:8000/>

按 `Ctrl+C` 会同时停止前后端及其子进程。也可以覆盖默认端口：

```powershell
.\start-dev.ps1 -BackendPort 8001 -FrontendPort 5174
```

## 常用检查

后端：

```powershell
.\ToolBoxBackEnd\.venv\Scripts\python.exe .\ToolBoxBackEnd\manage.py check
.\ToolBoxBackEnd\.venv\Scripts\python.exe .\ToolBoxBackEnd\manage.py test api
```

前端：

```powershell
npm --prefix .\ToolBoxFrontEnd run build
```
