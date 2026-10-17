import 'package:dio/dio.dart';

import 'feedback_exception.dart';

/// presign 返回结果。
class PresignResult {
  final String fileKey;
  final String uploadUrl;
  /// 必须一字不差回传给 PUT，后端签名绑定了 content-type。
  final String contentType;

  const PresignResult(this.fileKey, this.uploadUrl, this.contentType);
}

/// 取码结果。提交反馈时需原样回传到校验头，一次性使用、绑定 client_id。
class CodeTicket {
  final String centerId;
  final int timestamp;
  final String sn;
  final String nonce;
  final String code;

  const CodeTicket({
    required this.centerId,
    required this.timestamp,
    required this.sn,
    required this.nonce,
    required this.code,
  });
}

/// 后端 HTTP 层，统一注入 `X-Client-ID`。
class FeedbackApi {
  final Dio _dio;
  final String _clientId;

  FeedbackApi({required String baseUrl, required String clientId, Dio? dio})
      : _clientId = clientId,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Client-ID'] = _clientId;
        handler.next(options);
      },
    ));
  }

  String get clientId => _clientId;

  /// 1) 获取图片上传凭证。
  Future<PresignResult> presign({
    required String filename,
    required int size,
    required String mimeType,
  }) async {
    final res = await _dio.post('/api/v1/uploads/presign', data: {
      'filename': filename,
      'size': size,
      'mime_type': mimeType,
    });
    final d = res.data['data'] as Map;
    return PresignResult(
      d['file_key'] as String,
      d['upload_url'] as String,
      d['headers']['Content-Type'] as String,
    );
  }

  /// 2) PUT 图片到 COS。Content-Type 必须用 presign 返回的，否则 COS 返回 403。
  Future<void> putImage(PresignResult p, List<int> bytes) async {
    await _dio.put(
      p.uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': p.contentType}),
    );
  }

  /// 3) 确认上传，返回 attachment_id。
  Future<int> confirm(String fileKey) async {
    final res = await _dio.post('/api/v1/uploads/confirm', data: {'file_key': fileKey});
    return (res.data['data']['attachment_id'] as num).toInt();
  }

  /// 取一次性反馈校验码。校验码一次性、绑定 client_id，过期（默认 15 分钟）需重新取。
  Future<CodeTicket> issueCode({
    required String centerId,
    required String sn,
  }) async {
    final res = await _dio.post(
      '/api/v1/feedback-centers/$centerId/codes',
      data: {'sn': sn},
    );
    final d = res.data['data'] as Map;
    return CodeTicket(
      centerId: d['centerId'] as String,
      timestamp: (d['timestamp'] as num).toInt(),
      sn: d['sn'] as String,
      nonce: d['nonce'] as String,
      code: d['code'] as String,
    );
  }

  /// 提交反馈，返回 feedback_no。需先 [issueCode] 取到一次性 [CodeTicket]。
  Future<String> submit({
    required String requestId,
    required String content,
    required String contact,
    required CodeTicket ticket,
    List<int> attachmentIds = const [],
    Map<String, dynamic> extra = const {},
  }) async {
    final res = await _dio.post(
      '/api/v1/feedbacks',
      data: {
        'request_id': requestId,
        'content': content,
        'contact': contact,
        'attachment_ids': attachmentIds,
        'extra': extra,
      },
      options: Options(headers: {
        'X-Feedback-Center-Id': ticket.centerId,
        'X-Timestamp': ticket.timestamp.toString(),
        'X-SN': ticket.sn,
        'X-Nonce': ticket.nonce,
        'X-Code': ticket.code,
      }),
    );
    return res.data['data']['feedback_no'] as String;
  }

  /// 把任意异常转成 [FeedbackException]，方便上层统一提示。
  static FeedbackException toFeedback(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['code'] is int) {
        return FeedbackException(
          data['code'] as int,
          (data['message'] ?? '') as String,
          httpStatus: e.response?.statusCode,
        );
      }
      return FeedbackException(-1, '网络异常', httpStatus: e.response?.statusCode);
    }
    return const FeedbackException(-1, '网络异常');
  }
}
