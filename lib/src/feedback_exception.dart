/// 统一反馈异常，`code` 对应后端错误码表。
class FeedbackException implements Exception {
  final int code;
  final String message;
  final int? httpStatus;

  const FeedbackException(this.code, this.message, {this.httpStatus});

  /// 把后端错误码翻译成可直接给用户看的中文提示。
  String get userMessage {
    switch (code) {
      case 40002:
        return '初始化异常，请重启应用后再试';
      case 41301:
        return '图片过大，请压缩后重试';
      case 41501:
        return '图片格式不支持';
      case 42901:
        return '操作过于频繁，请稍后再试';
      case 40901:
        return '请勿重复提交';
      case 40101:
        return '无权限';
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
