import 'dart:typed_data';

import 'client_id_store.dart';
import 'device_info_helper.dart';
import 'feedback_api.dart';
import 'feedback_config.dart';
import 'feedback_uploader.dart';
import 'image_processor.dart';

/// SDK 门面，聚合各模块，提供一行式初始化与提交。
class FeedbackSdk {
  static FeedbackSdk? _instance;

  final FeedbackConfig config;
  final String clientId;
  final FeedbackApi api;
  final FeedbackUploader uploader;
  final DeviceInfoHelper deviceInfo;

  FeedbackSdk._({
    required this.config,
    required this.clientId,
    required this.api,
    required this.uploader,
    required this.deviceInfo,
  });

  static FeedbackSdk get instance =>
      _instance ?? (throw StateError('FeedbackSdk 未初始化，请先 await FeedbackSdk.init(...)'));

  /// 初始化（需在 runApp 前 await，或首次使用前完成）。
  static Future<FeedbackSdk> init(FeedbackConfig config) async {
    final clientId = await ClientIdStore().getOrCreate();
    final api = FeedbackApi(baseUrl: config.baseUrl, clientId: clientId);
    final uploader = FeedbackUploader(
      api: api,
      processor: ImageProcessor(
        longEdge: config.longEdge,
        maxBytes: config.maxImageBytes,
        jpegQuality: config.jpegQuality,
      ),
    );
    final sdk = FeedbackSdk._(
      config: config,
      clientId: clientId,
      api: api,
      uploader: uploader,
      deviceInfo: DeviceInfoHelper(),
    );
    _instance = sdk;
    return sdk;
  }

  /// 上传一张图片，返回 attachment_id。
  Future<int> uploadImage({required String filename, required Uint8List raw}) =>
      uploader.uploadImage(filename: filename, raw: raw);

  String newRequestId() => uploader.newRequestId();

  /// 提交反馈，返回 feedback_no。
  ///
  /// [extra] 会覆盖自动采集的同名字段；[requestId] 重试时复用同一个以幂等。
  Future<String> submit({
    required String content,
    required String contact,
    List<int> attachmentIds = const [],
    String? page,
    Map<String, dynamic> extra = const {},
    String? requestId,
  }) async {
    final device = await deviceInfo.collect(page: page);
    final merged = <String, dynamic>{
      'app_name': config.appName,
      if (config.school.isNotEmpty) 'school': config.school,
      ...device,
      ...extra,
    };
    return api.submit(
      requestId: requestId ?? newRequestId(),
      content: content,
      contact: contact,
      attachmentIds: attachmentIds,
      extra: merged,
    );
  }
}
