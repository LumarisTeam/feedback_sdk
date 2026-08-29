/// 统一反馈中心 Flutter SDK 公共入口。
///
/// 用法：
/// ```dart
/// final sdk = await FeedbackSdk.init(FeedbackConfig(
///   baseUrl: 'https://feedbackapi.luckyfishes.site',
///   appName: 'lumaris', // 或 'lumalis'
/// ));
/// ```
library feedback_sdk;

export 'src/feedback_config.dart';
export 'src/feedback_exception.dart';
export 'src/client_id_store.dart';
export 'src/image_processor.dart';
export 'src/device_info_helper.dart';
export 'src/feedback_api.dart';
export 'src/feedback_uploader.dart';
export 'src/feedback_sdk_facade.dart';
