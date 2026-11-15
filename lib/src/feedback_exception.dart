/// 高风险提交触发的人机验证挑战。
class CaptchaChallenge {
  /// `turnstile` 或 `hcaptcha`。
  final String provider;

  /// 可公开给验证码组件的 site key。
  final String siteKey;

  /// 验证 token 回传头，当前固定为 `X-Captcha-Token`。
  final String header;

  const CaptchaChallenge({
    required this.provider,
    required this.siteKey,
    this.header = 'X-Captcha-Token',
  });

  static CaptchaChallenge? fromResponseData(Object? data) {
    if (data is! Map) return null;
    final challenge = data['challenge'];
    if (challenge is! Map) return null;
    final provider = challenge['provider'];
    final siteKey = challenge['site_key'];
    if (provider is! String || siteKey is! String) return null;
    return CaptchaChallenge(
      provider: provider,
      siteKey: siteKey,
      header: challenge['header'] as String? ?? 'X-Captcha-Token',
    );
  }
}

/// 应用层取得人机验证 token 后返回；取消验证时返回 null。
typedef CaptchaTokenProvider = Future<String?> Function(
  CaptchaChallenge challenge,
);

/// 统一反馈异常，`code` 对应后端错误码表。
class FeedbackException implements Exception {
  final int code;
  final String message;
  final int? httpStatus;
  final CaptchaChallenge? challenge;

  const FeedbackException(
    this.code,
    this.message, {
    this.httpStatus,
    this.challenge,
  });

  /// 把后端错误码翻译成可直接给用户看的中文提示。
  String get userMessage {
    switch (code) {
      case 40002:
        return '初始化异常，请重启应用后再试';
      case 40003:
        return '请求已过期，请重试';
      case 40004:
        return '设备标识无效';
      case 40005:
        return '反馈校验失败，请重试';
      case 40006:
        return '请勿重复提交';
      case 41301:
        return '图片过大，请压缩后重试';
      case 41501:
        return '图片格式不支持';
      case 42901:
        return '操作过于频繁，请稍后再试';
      case 40901:
        return '请勿重复提交';
      case 40101:
        if (httpStatus == 404) return '反馈中心不存在';
        return '无权限';
      case 40102:
        return '反馈中心已停用';
      case 40103:
        return '反馈中心密钥已更新，请重试';
      case 40301:
        return '人机验证失败，请重试';
      case 42801:
        return '需要完成人机验证';
      case 50302:
        return '人机验证服务暂不可用，请稍后再试';
      case 40401:
        return '资源不存在';
      default:
        return message.isNotEmpty ? message : '网络异常，请稍后再试';
    }
  }

  @override
  String toString() => 'FeedbackException(code=$code, message=$message)';
}

/// 图片处理阶段抛出的异常（解码失败 / 压缩后仍超限等）。
class FeedbackFormatException extends FeedbackException {
  const FeedbackFormatException(String message) : super(40001, message);
}
