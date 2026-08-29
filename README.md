# feedback_sdk

LumarisTeam「统一反馈中心」Flutter SDK。封装匿名身份、图片压缩、图文反馈上传与提交，供「光序 / 光汇」两个 App 复用。

## 功能

- 匿名身份：本地生成并持久化 `client_id`，所有请求自动注入 `X-Client-ID`
- 图片处理：解码 → 校正 EXIF → 限制长边（默认 2000px）→ 转 JPG（透明图保留 PNG）→ 阶梯压缩到 ≤5MB
- 三段式上传：`presign → PUT COS → confirm`，含 confirm 幂等重试、presign 过期重取
- 提交反馈：自动生成 `request_id` 幂等，自动采集环境信息写入 `extra`
- 错误映射：后端错误码 → 中文提示

## 接入

### path 依赖（本地开发）

```yaml
dependencies:
  feedback_sdk:
    path: ../feedback_sdk
```

### git 依赖

```yaml
dependencies:
  feedback_sdk:
    git:
      url: https://github.com/LumarisTeam/feedback_sdk.git
      ref: main
```

## 使用

```dart
import 'package:feedback_sdk/feedback_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FeedbackSdk.init(FeedbackConfig(
    baseUrl: 'https://feedbackapi.luckyfishes.site',
    appName: 'lumaris', // 光序 = lumaris，光汇 = lumalis
    school: 'xauat',    // 学校 slug，多学校部署时填；单学校可省略
  ));
  runApp(const MyApp());
}
```

### 提交反馈（选图 + 上传 + 提交）

```dart
final sdk = FeedbackSdk.instance;

// 1. 选图（image_picker 是 App 侧依赖，SDK 不强制）
final files = await ImagePicker().pickMultiImage();
if (files.length > sdk.config.maxImageCount) {
  // 提示最多 6 张
}

// 2. 逐张上传
final attachmentIds = <int>[];
try {
  for (final f in files) {
    final raw = await f.readAsBytes();
    final id = await sdk.uploadImage(filename: f.name, raw: raw);
    attachmentIds.add(id);
  }

  // 3. 提交
  final requestId = sdk.newRequestId(); // 重试时复用同一个
  final no = await sdk.submit(
    requestId: requestId,
    content: '课表页面切换周次后闪退。',
    contact: '13800000000',
    attachmentIds: attachmentIds,
    page: '/course/schedule',
  );
  // 成功：提示「提交成功」，清空表单
} on FeedbackException catch (e) {
  showToast(e.userMessage);
} on DioException catch (e) {
  showToast(FeedbackApi.toFeedback(e).userMessage);
}
```

## 说明

- **选图不在 SDK 内**：SDK 只接收原始字节（`Uint8List`），选图用 `image_picker` 由 App 负责。
- **HEIC**：`image` 包不解码 HEIC；iOS 的 `image_picker` 默认会把 HEIC 转成 JPEG，Android 少见 HEIC，一般无需额外处理。
- **HTTP/HTTPS**：生产务必用 `https`；若联调用 `http`，iOS 需配 ATS 例外、Android 需 `usesCleartextTraffic`。
- **自动采集**：`extra` 会自动带上 `app_name / app_version / app_build / platform / os_version / device_model / page`。
