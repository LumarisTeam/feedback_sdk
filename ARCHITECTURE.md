# 统一反馈中心 — 核心文档

> 本文件是「统一反馈中心」项目的核心上下文，压缩 / 换会话后优先读这里。
> 后端 PRD（v1.0）原文见 `E:\qq文件\统一反馈后端PRD (1).md`。
> Flutter SDK 包在 `C:\Users\Qu\feedback_sdk\`。

## 1. 项目定位

第三方教务软件「Bug 反馈中心」：用户在 Flutter 客户端**匿名**提交 Bug 描述 + 联系方式 + 图片；后端保存反馈与图片元数据；管理员通过 web 管理页查看。

**本期不做**：用户登录、历史反馈、状态流转、评论回复、消息通知、统计报表、图片审核、缩略图、EXIF 清理。

## 2. 总体架构

```
┌──────────────┐   ┌──────────────┐
│ 光序 Lumaris  │   │ 光汇 Lumalis  │   Flutter App
└──────┬───────┘   └──────┬───────┘
       │   共用 feedback_sdk │
       └─────────┬──────────┘
                 │ HTTPS JSON (+ X-Client-ID)
                 ▼
        ┌─────────────────┐
        │   Go API 服务     │  单实例 / Gin / 进程内限流
        └────────┬────────┘
     ┌───────────┴───────────┐
     ▼                       ▼
┌───────────┐        ┌──────────────────┐
│ PostgreSQL │        │   腾讯云 COS       │
│ feedback   │        │  图片 · 完全私有     │
│ attachment │        │  Presign PUT/GET  │
└───────────┘        └──────────────────┘
                 ▲
                 │ Bearer ADMIN_API_TOKEN
        ┌────────┴────────┐
        │ React/Vue 管理页 │   Web 前端
        └─────────────────┘
```

## 3. 分工与技术栈

| 模块 | 技术 | 负责人 |
|---|---|---|
| Flutter SDK（嵌入光序/光汇） | Flutter + dio + image | 屈艺轩 |
| Web 管理页 | React / Vue | 屈艺轩 |
| 后端 | Go（Gin + pgx/v5 + 腾讯云 COS SDK） | 刘嘉玲 / 青钰蓝 |
| 数据库 | PostgreSQL | — |
| 对象存储 | 腾讯云 COS（完全私有） | — |

- 后端仓库：https://github.com/LumarisTeam/Lens_Backend
- 线上 API：`http://feedbackapi.luckyfishes.site/`

## 4. 核心约束

### 4.1 匿名身份
- `client_id`：UUID，首次启动生成 + 持久化，卸载重装可变化，绝不每次请求重新生成。
- 所有请求带 `X-Client-ID`（缺失 → 40002）。

### 4.2 文本
- `content` 必填 1~2000 字符；`contact` 必填 1~128 字符；`extra` 可选 JSON，硬限制 8KB。

### 4.3 图片
- 最多 6 张，单张 ≤5MB，支持 JPG / PNG / WebP。
- 格式转换 + 压缩由**客户端负责**；后端在 confirm 阶段校验文件头（magic number）。

### 4.4 安全（关键决策）
- COS 桶**完全私有**，图片访问用动态 Presign GET URL（15 分钟），不暴露固定 URL（防盗刷）。
- Presign PUT 绑定 `Content-Type`；**Content-Length 钉死为 presign 声明的 `size`**（腾讯云 COS 预签名不支持 `content-length-range` 区间，后端改为钉死长度，仍从签名层杜绝超 5MB）。含义：**PUT 的字节数必须与 presign 的 `size` 完全一致，否则 COS 403**。SDK 已保证 `size = 压缩后字节数` 且 PUT 同一份字节。
- 产品线通过「反馈中心 ID + sn」区分：取码 `POST /feedback-centers/{center_id}/codes` 携带 `{sn}`，光序 `lumaris-prod` / 光汇 `lumalis-prod`（**无 channel 字段**）。
- **多学校**：`extra.school` 标识学校（slug，如 `xauat`）。同一产品铺多校，靠 `center_id + school` 共同区分；SDK 配置项 `FeedbackConfig.school` 自动写入，为空则跳过。
- 管理员 token 仅 `ADMIN_API_TOKEN`，不能写入客户端。

## 5. 接口清单

### 客户端（需带 X-Client-ID）
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 健康检查 |
| POST | `/api/v1/uploads/presign` | 拿 `file_key` + `upload_url` + `headers.Content-Type` |
| POST | `/api/v1/uploads/confirm` | 返回 `attachment_id`（幂等） |
| POST | `/api/v1/feedback-centers/{center_id}/codes` | 取一次性校验码（body `{sn}`，返回 `timestamp/nonce/code`） |
| POST | `/api/v1/feedbacks` | 返回 `feedback_no`（`request_id` 幂等；需 5 个校验头） |

### 管理员（Bearer ADMIN_API_TOKEN）
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/admin/feedbacks` | 列表（分页/关键词/时间/是否有图） |
| GET | `/api/v1/admin/feedbacks/{feedback_no}` | 详情（图片为临时签名 URL，15 分钟过期） |

## 6. 错误码

| HTTP | code | message | 前端处理 |
|---|---:|---|---|
| 400 | 40001 | 参数错误 | 提示参数不合法 |
| 400 | 40002 | 缺少 X-Client-ID | 提示初始化异常 |
| 401 | 40101 | 未授权 | 管理员 token 错误 |
| 404 | 40401 | 资源不存在 | — |
| 409 | 40901 | 重复提交 | 按幂等处理 |
| 413 | 41301 | 文件过大 | 提示图片过大 |
| 415 | 41501 | 文件类型不支持 | 提示格式不支持 |
| 429 | 42901 | 请求过于频繁（Retry-After: 60） | 提示稍后再试 |
| 500 | 50001 | 服务内部错误 | — |

## 7. 上传三段式（核心流程）

```
1. POST /uploads/presign   声明 filename / size / mime_type
2. PUT 图片字节 → upload_url    Content-Type 必须用 presign 返回的
3. POST /uploads/confirm   携带 file_key
```

重试规则：
- confirm 网络失败 / 5xx → 用**同一 file_key** 重试（后端幂等返回同一 attachment_id）。
- PUT 403（presign 过期 / 签名不符）→ **重新 presign** 再 PUT，不复用旧 URL。

## 8. Flutter SDK 核心函数定义

包：`feedback_sdk`，公共出口 `lib/feedback_sdk.dart`。

| 类 | 核心方法 | 职责 |
|---|---|---|
| `FeedbackSdk` | `init(config)` / `submit(...)` / `uploadImage(...)` / `newRequestId()` | 门面：初始化 + 提交 |
| `FeedbackConfig` | 构造参数 `baseUrl` / `centerId` / `sn` / `longEdge` / `maxImageBytes` … | 全局配置 |
| `FeedbackApi` | `presign()` / `putImage()` / `confirm()` / `issueCode()` / `submit()` / `toFeedback()` | HTTP 层，注入 X-Client-ID |
| `FeedbackUploader` | `uploadImage()` / `_confirmWithRetry()` | 上传编排 + 重试 |
| `ImageProcessor` | `process(raw) → ProcessedImage` | 解码/EXIF/长边限制/转码/阶梯压缩 |
| `ClientIdStore` | `getOrCreate()` | 匿名 ID 持久化 |
| `DeviceInfoHelper` | `collect({page})` | 自动采集 extra（版本/平台/机型/OS） |
| `FeedbackException` | `userMessage` | 错误码 → 中文提示 |

图片压缩关键点（`ImageProcessor`）：
- `bakeOrientation` 校正 EXIF 方向。
- 长边 > 2000 才缩放，小图**不放大**。
- 透明图保留 PNG，否则转 JPG（转 JPG 会丢透明变黑底）。

## 9. 联调状态

- 线上 `/healthz` 200 ✅
- presign → PUT → confirm 全链路验证通过 ✅（返回 attachment_id 正常）
- 待办：真机选图上传、反馈表单 UI、web 管理页（含图片凭证过期重试）、`baseUrl` 换 https。
