# feedback_sdk

LumarisTeam「统一反馈中心」Flutter SDK。封装匿名身份、图片压缩、图文反馈上传与提交，供「光序 / 光汇」两个 App 复用。

## 功能

- 匿名身份：本地生成并持久化 `client_id`，所有请求自动注入 `X-Client-ID`
- 图片处理：解码 → 校正 EXIF → 限制长边（默认 2000px）→ 转 JPG（透明图保留 PNG）→ 阶梯压缩到 ≤5MB
- 三段式上传：`presign → PUT COS → confirm`，含 confirm 幂等重试、presign 过期重取
- 提交反馈：自动取一次性校验码并携带校验头，自动生成 `request_id` 幂等
- 高风险挑战：解析后端 `42801`，通过 `captchaTokenProvider` 获取 Turnstile/hCaptcha token，自动重新取码并重试
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
    centerId: 'fc_xxx',
    sn: 'lumaris-prod',
    school: 'xauat',    // 学校 slug，多学校部署时填；单学校可省略
  ));
  runApp(const MyApp());
}
```

`centerId` 与 `sn` 必须和反馈中心管理页配置一致，否则取码会返回 `40004`。每次 `submit` 都会重新取一枚
一次性校验码；重试时请复用同一个 `requestId`，但不要复用旧 code。

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
    captchaTokenProvider: (challenge) async {
      // 应用层根据 challenge.provider / challenge.siteKey 打开对应验证码组件，
      // 完成后返回 token；用户取消时返回 null。
      return showCaptchaAndGetToken(
        provider: challenge.provider,
        siteKey: challenge.siteKey,
      );
    },
  );
  // 成功：提示「提交成功」，清空表单
} on FeedbackException catch (e) {
  showToast(e.userMessage);
} on DioException catch (e) {
  showToast(FeedbackApi.toFeedback(e).userMessage);
}
```

### 本地真实联调测试

先按后端 README 启动 PostgreSQL、Redis 和服务，并在管理端创建一个可用的反馈中心。然后指定中心参数运行
SDK 的真实 HTTP 测试；未设置这些环境变量时，集成用例会自动跳过：

```powershell
$env:FEEDBACK_TEST_BASE_URL = "http://127.0.0.1:8080"
$env:FEEDBACK_TEST_CENTER_ID = "fc_xxx"
$env:FEEDBACK_TEST_SN = "lumaris-prod"
flutter test test/backend_integration_test.dart
```

该用例会走真实的取码、提交和附件绑定链路。图片用例要求后端连接真实 COS，或指向本地假 COS 测试端点。

### Flutter Web 验证

`example/` 是一个直接调用当前 SDK 的 Flutter Web 工程，包含文本提交和图片上传：

```powershell
cd example
flutter pub get --offline
flutter analyze
flutter build web --release --no-wasm-dry-run
python -m http.server 8081 --bind 127.0.0.1 --directory build\web
```

打开 `http://127.0.0.1:8081/`。页面可以在光序和光汇两个反馈中心之间切换；
默认使用本地中心 `fc_06grayn2c9yt6rs7eqp92hn2hg` / `lumaris-demo`，光汇中心为
`fc_06grfzb75me17em6wzzf9ck0dg` / `lumalis-demo`。可通过
`--dart-define=FEEDBACK_BASE_URL=...`、`LUMARIS_CENTER_ID`、`LUMARIS_SN`、
`LUMALIS_CENTER_ID`、`LUMALIS_SN` 覆盖。后端需要允许
`http://127.0.0.1:8081` 的 CORS。

## 说明

- **选图不在 SDK 内**：SDK 只接收原始字节（`Uint8List`），选图用 `image_picker` 由 App 负责。
- **HEIC**：`image` 包不解码 HEIC；iOS 的 `image_picker` 默认会把 HEIC 转成 JPEG，Android 少见 HEIC，一般无需额外处理。
- **HTTP/HTTPS**：生产务必用 `https`；若联调用 `http`，iOS 需配 ATS 例外、Android 需 `usesCleartextTraffic`。
- **后端版本**：SDK 依赖 `POST /api/v1/feedback-centers/:center_id/codes`。该接口返回 404 时说明服务端仍是旧版，
  不能用 SDK 自动降级绕过校验码。
- **人机验证**：后端默认 `CAPTCHA_PROVIDER=off` 时不触发挑战。启用后，高风险提交返回 `42801`；
  SDK 会用 `CaptchaChallenge.provider` / `siteKey` 调用应用层验证码组件，拿到 token 后重新取码，再携带
  `X-Captcha-Token` 自动重试一次。
- **自动采集**：`extra` 会自动带上 `app_name / app_version / app_build / platform / os_version / device_model / page`。
