# evnote

基于 **事件溯源（Event Sourcing）** 和 **代数效应（Algebraic Effects）** 架构的个人笔记 Web 应用，使用 Zig 编写。

## 特性

- 笔记 CRUD — 创建、编辑、查看、删除 Markdown 笔记
- 版本历史 — 每次编辑自动保存历史版本，可回溯
- GitHub 风格 Markdown — 支持表格、删除线、任务列表、自动链接（cmark-gfm）
- 用户认证 — 注册/登录，Session 持久化
- 文件管理 — 上传、查看、删除文件，可插入笔记
- 事件溯源 — 所有变更记录为事件，状态由事件重放重建
- 代数效应 — 通过 Effect/Handler 模式分离业务逻辑与实现
- 单文件部署 — 编译为单个二进制，零运行时依赖

## 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Zig |
| HTTP 服务 | 自实现（`src/web/server.zig`） |
| 路由 | 自实现（`src/web/router.zig`） |
| 存储 | SQLite（可切换内存实现） |
| Markdown | cmark-gfm（GFM 标准） |
| 前端 | 原生 HTML + CSS + JS（无框架） |

## 快速开始

```bash
# 构建
zig build

# 运行（默认端口 8080）
zig build run

# 测试
zig build test
```

打开 `http://localhost:8080` 即可使用。

## 项目结构

```
src/
├── domain/        # 领域模型（Note、User、Event、Diff）
│   ├── note.zig
│   ├── user.zig
│   ├── event.zig
│   ├── diff.zig
│   └── error.zig
├── ops/           # 操作接口（Storage、Auth、Render、Log）
├── effect/        # 上下文与依赖注入
├── service/       # 业务逻辑（Note、User、Auth、Version）
├── handler/       # 接口实现（SQLite、cmark、日志、测试替身）
└── web/           # HTTP 层
    ├── server.zig
    ├── router.zig
    ├── json.zig
    ├── multipart.zig
    ├── static.zig
    ├── index.html
    └── handler/   # HTTP 处理器
```

## API 概览

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/auth/login` | 登录 |
| POST | `/api/auth/register` | 注册 |
| GET | `/api/notes` | 笔记列表 |
| POST | `/api/notes` | 创建笔记 |
| GET | `/api/notes/:id` | 获取笔记 |
| PUT | `/api/notes/:id` | 更新笔记 |
| DELETE | `/api/notes/:id` | 删除笔记 |
| GET | `/api/notes/:id/versions` | 版本历史 |
| GET | `/api/notes/:id/versions/:seq` | 指定版本 |
| POST | `/api/files` | 上传文件 |
| GET | `/api/files` | 文件列表 |
| GET | `/api/files/:id` | 获取文件 |
| DELETE | `/api/files/:id` | 删除文件 |
| POST | `/api/render` | 渲染 Markdown |

## 架构说明

### 事件溯源

所有笔记操作（创建、编辑、删除）均以事件形式存储。笔记的当前状态通过重放事件序列重建。每次编辑记录差异（diff），而非全量快照，便于版本回溯。

### 代数效应

通过 `Effect` 接口定义行为，`Handler` 提供具体实现。业务逻辑不依赖具体存储或渲染实现，便于测试和切换。

## 许可证

MIT
