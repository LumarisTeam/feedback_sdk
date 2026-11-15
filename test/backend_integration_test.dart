import 'dart:io';
import 'dart:typed_data';

import 'package:feedback_sdk/feedback_sdk.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['FEEDBACK_TEST_BASE_URL'];
  final centerId = Platform.environment['FEEDBACK_TEST_CENTER_ID'];
  final sn = Platform.environment['FEEDBACK_TEST_SN'];
  final skipReason = baseUrl == null || centerId == null || sn == null
      ? 'Set FEEDBACK_TEST_BASE_URL, FEEDBACK_TEST_CENTER_ID and '
          'FEEDBACK_TEST_SN to run against a local backend.'
      : null;

  test(
    'real backend accepts an SDK-issued code and feedback payload',
    () async {
      final api = FeedbackApi(
        baseUrl: baseUrl!,
        clientId: 'sdk-integration-${DateTime.now().microsecondsSinceEpoch}',
      );

      final code = await api.issueCode(centerId: centerId!, sn: sn!);
      final feedbackNo = await api.submit(
        requestId: 'sdk-integration-${DateTime.now().microsecondsSinceEpoch}',
        content: 'SDK/backend integration test',
        contact: '13800000000',
        code: code,
        extra: const {'app_name': 'spoofed', 'source': 'dart-sdk'},
      );

      expect(feedbackNo, isNotEmpty);
    },
    skip: skipReason,
  );

  test(
    'real backend accepts the SDK image upload chain',
    () async {
      final api = FeedbackApi(
        baseUrl: baseUrl!,
        clientId: 'sdk-image-${DateTime.now().microsecondsSinceEpoch}',
      );
      final uploader = FeedbackUploader(api: api);
      final image = img.Image(width: 16, height: 16);
      img.fill(image, color: img.ColorRgb8(214, 51, 132));
      final raw = Uint8List.fromList(img.encodePng(image));

      final attachmentId = await uploader.uploadImage(
        filename: 'sdk-integration.png',
        raw: raw,
      );
      final code = await api.issueCode(centerId: centerId!, sn: sn!);
      final feedbackNo = await api.submit(
        requestId: 'sdk-image-${DateTime.now().microsecondsSinceEpoch}',
        content: 'SDK image integration test',
        contact: '13800000000',
        code: code,
        attachmentIds: [attachmentId],
        extra: const {'source': 'dart-sdk-image'},
      );

      expect(attachmentId, greaterThan(0));
      expect(feedbackNo, isNotEmpty);
    },
    skip: skipReason,
  );
}
