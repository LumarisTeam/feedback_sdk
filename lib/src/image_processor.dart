import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'feedback_exception.dart';

/// 图片处理结果：已压缩的字节 + 对应 MIME。
class ProcessedImage {
  final Uint8List bytes;
  final String mimeType; // image/jpeg 或 image/png

  const ProcessedImage(this.bytes, this.mimeType);
}

enum _ImageFormat { jpeg, png, webp, gif, heic, unknown }

/// 图片压缩 / 转码。
///
/// 流程：格式校验（只收 JPG/PNG/WebP，HEIC 转码，其余拒绝）→ 校正 EXIF 方向 →
/// 限制长边 → 转 JPG（透明图保留 PNG）→ 阶梯压缩兜底。
class ImageProcessor {
  final int longEdge;
  final int maxBytes;
  final int jpegQuality;

  ImageProcessor({
    this.longEdge = 2000,
    this.maxBytes = 5 * 1024 * 1024,
    this.jpegQuality = 80,
  });

  Future<ProcessedImage> process(Uint8List raw) async {
    final format = _detectFormat(raw);

    if (format == _ImageFormat.heic) {
      // iPhone 相机默认 HEIC，`image` 包不解码，先用原生能力转 JPEG。
      raw = await _transcodeHeicToJpeg(raw);
    } else if (format != _ImageFormat.jpeg &&
        format != _ImageFormat.png &&
        format != _ImageFormat.webp) {
      // GIF / BMP / 未知格式一律拒绝，避免走到解码环节报出误导性错误。
      throw const FeedbackFormatException('图片格式不支持，仅支持 JPG/PNG/WebP');
    }

    try {
      return _compress(raw);
    } on FeedbackException {
      rethrow;
    } catch (_) {
      // 解码 / 编码阶段的异常统一归为格式问题，而不是泄漏成「网络异常」。
      throw const FeedbackFormatException('图片处理失败，请更换图片');
    }
  }

  ProcessedImage _compress(Uint8List raw) {
    img.Image? src = img.decodeImage(raw);
    if (src == null) throw const FeedbackFormatException('无法解码图片');
    src = img.bakeOrientation(src); // 应用 EXIF 方向，避免照片横躺

    final hasAlpha = src.hasAlpha; // 透明图强转 JPG 会变黑底，保留 PNG

    // 阶梯：长边 + 质量 从高到低逐级尝试，直到 ≤ maxBytes。
    final ladder = <(int, int)>[
      (longEdge, jpegQuality),
      (longEdge, (jpegQuality * 0.75).round()),
      ((longEdge * 0.8).round(), 60),
      ((longEdge * 0.64).round(), 50),
      ((longEdge * 0.48).round(), 40),
    ];

    for (final (edge, quality) in ladder) {
      final resized = _resizeLongEdge(src, edge);
      final bytes = hasAlpha
          ? Uint8List.fromList(img.encodePng(resized))
          : Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (bytes.lengthInBytes <= maxBytes) {
        return ProcessedImage(bytes, hasAlpha ? 'image/png' : 'image/jpeg');
      }
    }
    throw const FeedbackFormatException('图片过大，请裁剪后重试');
  }

  Future<Uint8List> _transcodeHeicToJpeg(Uint8List raw) async {
    Uint8List? jpeg;
    try {
      jpeg = await FlutterImageCompress.compressWithList(
        raw,
        quality: 100,
        format: CompressFormat.jpeg,
      );
    } catch (_) {
      jpeg = null; // Android 等平台可能不解 HEIC，归到「无法解码」提示
    }
    if (jpeg == null || jpeg.isEmpty) {
      throw const FeedbackFormatException('无法解码 HEIC 图片');
    }
    return jpeg;
  }

  _ImageFormat _detectFormat(Uint8List bytes) {
    if (bytes.length < 12) return _ImageFormat.unknown;
    // JPEG: FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _ImageFormat.jpeg;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return _ImageFormat.png;
    }
    // GIF: 47 49 46 38 ("GIF8")
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return _ImageFormat.gif;
    }
    // WebP: 52 49 46 46 ("RIFF") ... 57 45 42 50 ("WEBP")
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return _ImageFormat.webp;
    }
    if (_isHeic(bytes)) return _ImageFormat.heic;
    return _ImageFormat.unknown;
  }

  /// HEIC 是 ISO-BMFF：offset 4 起为 'ftyp'，随后 4 字节为 major brand。
  bool _isHeic(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
    if (ftyp != 'ftyp') return false;
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    const brands = {
      'heic', 'heix', 'hevc', 'hevx',
      'heim', 'heis', 'hevm', 'hevs',
      'mif1', 'msf1',
    };
    return brands.contains(brand);
  }

  /// 仅在原图长边大于 `edge` 时才缩放，小图不放大（修正 PRD 伪代码的 minWidth/minHeight 坑）。
  img.Image _resizeLongEdge(img.Image src, int edge) {
    final longest = src.width > src.height ? src.width : src.height;
    if (longest <= edge) return src;
    final scale = edge / longest;
    return img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
