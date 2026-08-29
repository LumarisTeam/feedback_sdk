/// 反馈 SDK 全局配置。
class FeedbackConfig {
  /// 后端地址，形如 https://feedbackapi.luckyfishes.site
  final String baseUrl;

  /// 产品线标识，区分「光序 / 光汇」：
  /// 光序 = 'lumaris'，光汇 = 'lumalis'。会写入 extra.app_name。
  final String appName;

  /// 学校标识（slug），多学校部署时必填，如 'xauat'。会写入 extra.school。
  /// 为空则不写入 extra（兼容单学校场景）。
  final String school;

  /// 最多图片数量（后端限制 6 张）。
  final int maxImageCount;

  /// 单张图片最大字节数（后端限制 5MB）。
  final int maxImageBytes;

  /// 反馈描述最大字符数（后端限制 2000）。
  final int maxContentLength;

  /// 联系方式最大字符数（后端限制 128）。
  final int maxContactLength;

  /// 图片压缩后的长边上限（px）。
  final int longEdge;

  /// JPEG 初始压缩质量（0~100）。
  final int jpegQuality;

  const FeedbackConfig({
    required this.baseUrl,
    required this.appName,
    this.school = '',
    this.maxImageCount = 6,
    this.maxImageBytes = 5 * 1024 * 1024,
    this.maxContentLength = 2000,
    this.maxContactLength = 128,
    this.longEdge = 2000,
    this.jpegQuality = 80,
  });
}
