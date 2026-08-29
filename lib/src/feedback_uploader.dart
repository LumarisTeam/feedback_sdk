import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'feedback_api.dart';
import 'image_processor.dart';

/// 上传编排：presign → PUT → confirm，含重试逻辑。
class FeedbackUploader {
  final FeedbackApi api;
  final ImageProcessor processor;
  final _uuid = const Uuid();

  FeedbackUploader({required this.api, ImageProcessor? processor})
      : processor = processor ?? ImageProcessor();

  /// 上传一张图片，返回 attachment_id。
  Future<int> uploadImage({required String filename, required Uint8List raw}) async {
    final img = await processor.process(raw);

    // 1. presign
    var presign = await api.presign(
      filename: filename,
      size: img.bytes.length,
      mimeType: img.mimeType,
    );

    // 2. PUT；403 说明凭证过期 / 签名不符 → 重新 presign 再传一次
    try {
      await api.putImage(presign, img.bytes);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        presign = await api.presign(
          filename: filename,
          size: img.bytes.length,
          mimeType: img.mimeType,
        );
        await api.putImage(presign, img.bytes);
      } else {
        rethrow;
      }
    }

    // 3. confirm（幂等：网络失败 / 5xx 用同一 file_key 重试）
    return _confirmWithRetry(presign.fileKey);
  }

  Future<int> _confirmWithRetry(String fileKey) async {
    const maxRetry = 3;
    for (var i = 0; ; i++) {
      try {
        return await api.confirm(fileKey);
      } on DioException catch (e) {
        if (!_isRetryable(e) || i >= maxRetry - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << i)); // 1s, 2s 退避
      }
    }
  }

  /// 仅网络错误 / 服务端错误重试；429、4xx 不重试直接抛。
  bool _isRetryable(DioException e) {
    final status = e.response?.statusCode;
    return status == null || status >= 500;
  }

  /// 每次点提交生成新 request_id；失败重试时复用同一个（保证幂等）。
  String newRequestId() => _uuid.v4();
}
