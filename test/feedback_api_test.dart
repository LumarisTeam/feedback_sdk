import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:feedback_sdk/src/feedback_api.dart';
import 'package:test/test.dart';

class _RecordedRequest {
  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });
}

void main() {
  test('plain-text 404 maps to backend version error', () {
    final request =
        RequestOptions(path: '/api/v1/feedback-centers/fc_old/codes');
    final error = FeedbackApi.toFeedback(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 404,
          data: '404 page not found',
        ),
      ),
    );

    expect(error.httpStatus, 404);
    expect(error.userMessage, '反馈服务版本不兼容，请联系开发者');
  });

  test('missing feedback center uses the backend 404 message', () {
    final request =
        RequestOptions(path: '/api/v1/feedback-centers/fc_missing/codes');
    final error = FeedbackApi.toFeedback(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 404,
          data: {
            'code': 40101,
            'message': '反馈中心不存在',
          },
        ),
      ),
    );

    expect(error.userMessage, '反馈中心不存在');
  });

  test('client id is not sent to presigned COS URL', () async {
    final apiServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final cosServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => apiServer.close(force: true));
    addTearDown(() => cosServer.close(force: true));

    String? cosClientId;
    cosServer.listen((request) async {
      cosClientId = request.headers.value('x-client-id');
      await request.drain<void>();
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });

    final api = FeedbackApi(
      baseUrl: 'http://127.0.0.1:${apiServer.port}',
      clientId: 'client-not-for-cos',
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${apiServer.port}')),
    );
    await api.putImage(
      PresignResult(
        'feedback/test.jpg',
        'http://127.0.0.1:${cosServer.port}/feedback/test.jpg',
        'image/jpeg',
      ),
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
    );

    expect(cosClientId, isNull);
  });

  test('feedback code and submit requests match backend contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requests = <_RecordedRequest>[];
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      requests.add(
        _RecordedRequest(
          method: request.method,
          path: request.uri.path,
          headers: {
            'x-client-id': request.headers.value('x-client-id') ?? '',
            'x-feedback-center-id':
                request.headers.value('x-feedback-center-id') ?? '',
            'x-timestamp': request.headers.value('x-timestamp') ?? '',
            'x-sn': request.headers.value('x-sn') ?? '',
            'x-nonce': request.headers.value('x-nonce') ?? '',
            'x-code': request.headers.value('x-code') ?? '',
            'x-captcha-token': request.headers.value('x-captcha-token') ?? '',
          },
          body: rawBody.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(rawBody) as Map<String, dynamic>,
        ),
      );

      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/codes')) {
        request.response.write(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'centerId': 'fc_test',
              'timestamp': 1729760000,
              'sn': 'lumaris-prod',
              'nonce': 'nonce-001',
              'code': 'signed-code',
              'expireAt': '2026-10-24T08:10:00Z',
            },
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {'feedback_no': 'FB202610240001'},
          }),
        );
      }
      await request.response.close();
    });

    final api = FeedbackApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      clientId: 'client-001',
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')),
    );
    final code = await api.issueCode(centerId: 'fc_test', sn: 'lumaris-prod');
    final feedbackNo = await api.submit(
      requestId: 'request-001',
      content: '课表页面切换周次后闪退',
      contact: '13800000000',
      code: code,
      attachmentIds: const [12],
      extra: const {'app_version': '1.0.0'},
      captchaToken: 'captcha-token-001',
    );

    expect(feedbackNo, 'FB202610240001');
    expect(requests, hasLength(2));

    final issueCode = requests[0];
    expect(issueCode.method, 'POST');
    expect(issueCode.path, '/api/v1/feedback-centers/fc_test/codes');
    expect(issueCode.headers['x-client-id'], 'client-001');
    expect(issueCode.body, {'sn': 'lumaris-prod'});

    final submit = requests[1];
    expect(submit.method, 'POST');
    expect(submit.path, '/api/v1/feedbacks');
    expect(submit.headers['x-client-id'], 'client-001');
    expect(submit.headers['x-feedback-center-id'], 'fc_test');
    expect(submit.headers['x-timestamp'], '1729760000');
    expect(submit.headers['x-sn'], 'lumaris-prod');
    expect(submit.headers['x-nonce'], 'nonce-001');
    expect(submit.headers['x-code'], 'signed-code');
    expect(submit.headers['x-captcha-token'], 'captcha-token-001');
    expect(submit.body, {
      'request_id': 'request-001',
      'content': '课表页面切换周次后闪退',
      'contact': '13800000000',
      'attachment_ids': [12],
      'extra': {'app_version': '1.0.0'},
    });
  });

  test('428 response exposes captcha challenge metadata', () {
    final request = RequestOptions(path: '/api/v1/feedbacks');
    final error = FeedbackApi.toFeedback(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 428,
          data: {
            'code': 42801,
            'message': '需要完成人机验证',
            'data': {
              'challenge': {
                'provider': 'turnstile',
                'site_key': 'site-key',
                'header': 'X-Captcha-Token',
              },
            },
          },
        ),
      ),
    );

    expect(error.code, 42801);
    expect(error.challenge?.provider, 'turnstile');
    expect(error.challenge?.siteKey, 'site-key');
    expect(error.challenge?.header, 'X-Captcha-Token');
  });
}
