// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:feedback_sdk/feedback_sdk.dart';
import 'package:flutter/material.dart';

const _apiBaseUrl = String.fromEnvironment(
  'FEEDBACK_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

class FeedbackApp {
  const FeedbackApp({
    required this.key,
    required this.label,
    required this.centerId,
    required this.sn,
  });

  final String key;
  final String label;
  final String centerId;
  final String sn;
}

const _apps = [
  FeedbackApp(
    key: 'lumaris',
    label: '光序',
    centerId: String.fromEnvironment(
      'LUMARIS_CENTER_ID',
      defaultValue: 'fc_06grayn2c9yt6rs7eqp92hn2hg',
    ),
    sn: String.fromEnvironment(
      'LUMARIS_SN',
      defaultValue: 'lumaris-demo',
    ),
  ),
  FeedbackApp(
    key: 'lumalis',
    label: '光汇',
    centerId: String.fromEnvironment(
      'LUMALIS_CENTER_ID',
      defaultValue: 'fc_06grfzb75me17em6wzzf9ck0dg',
    ),
    sn: String.fromEnvironment(
      'LUMALIS_SN',
      defaultValue: 'lumalis-demo',
    ),
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FeedbackSdk.init(
    FeedbackConfig(
      baseUrl: _apiBaseUrl,
      appName: _apps.first.key,
      centerId: _apps.first.centerId,
      sn: _apps.first.sn,
    ),
  );
  runApp(const FeedbackWebDemo());
}

class FeedbackWebDemo extends StatelessWidget {
  const FeedbackWebDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter SDK Web Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F4F3),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFC9D2D7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFC9D2D7)),
          ),
        ),
      ),
      home: const FeedbackPage(),
    );
  }
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _contentController = TextEditingController();
  final _contactController = TextEditingController();
  final List<int> _attachmentIds = [];
  final List<String> _attachmentNames = [];
  html.FileUploadInputElement? _imageInput;
  FeedbackApp _selectedApp = _apps.first;
  bool _submitting = false;
  bool _uploadingImages = false;
  bool _switchingApp = false;
  String? _feedbackNo;
  String? _error;

  FeedbackSdk get _sdk => FeedbackSdk.instance;

  @override
  void initState() {
    super.initState();
    final input = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png,image/webp'
      ..multiple = true
      ..style.display = 'none';
    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) return;
      final selected = List<html.File>.from(files);
      input.value = '';
      _uploadImages(selected);
    });
    html.document.body?.children.add(input);
    _imageInput = input;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    _imageInput?.remove();
    super.dispose();
  }

  Future<void> _uploadImages(List<html.File> files) async {
    setState(() {
      _uploadingImages = true;
      _error = null;
    });
    try {
      for (final file in files) {
        final reader = html.FileReader();
        reader.readAsDataUrl(file);
        await reader.onLoad.first;
        final dataUrl = reader.result as String?;
        final comma = dataUrl?.indexOf(',') ?? -1;
        if (dataUrl == null || comma < 0) {
          throw StateError('无法读取 ${file.name}');
        }
        final attachmentId = await _sdk.uploadImage(
          filename: file.name,
          raw: Uint8List.fromList(base64Decode(dataUrl.substring(comma + 1))),
        );
        if (!mounted) return;
        setState(() {
          _attachmentIds.add(attachmentId);
          _attachmentNames.add(file.name);
        });
      }
    } on FeedbackException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '图片上传失败：$error');
    } finally {
      if (mounted) setState(() => _uploadingImages = false);
    }
  }

  Future<void> _selectApp(FeedbackApp app) async {
    if (app.key == _selectedApp.key || _switchingApp) return;
    setState(() {
      _switchingApp = true;
      _error = null;
      _feedbackNo = null;
    });
    try {
      await FeedbackSdk.init(
        FeedbackConfig(
          baseUrl: _apiBaseUrl,
          appName: app.key,
          centerId: app.centerId,
          sn: app.sn,
        ),
      );
      if (!mounted) return;
      setState(() {
        _selectedApp = app;
        _attachmentIds.clear();
        _attachmentNames.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '切换应用失败：$error');
    } finally {
      if (mounted) setState(() => _switchingApp = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final feedbackNo = await _sdk.submit(
        content: _contentController.text.trim(),
        contact: _contactController.text.trim(),
        attachmentIds: _attachmentIds,
        page: '/flutter-web-demo',
        extra: const {'source': 'flutter-web-demo'},
      );
      if (!mounted) return;
      setState(() => _feedbackNo = feedbackNo);
    } on FeedbackException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.userMessage);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '提交失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    setState(() {
      _feedbackNo = null;
      _error = null;
      _contentController.clear();
      _contactController.clear();
      _attachmentIds.clear();
      _attachmentNames.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 48),
                  const Text(
                    'Flutter Web 反馈测试',
                    style: TextStyle(
                      color: Color(0xFF172A23),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '这个页面直接使用 feedback_sdk，而不是 TypeScript 仿写。',
                    style: TextStyle(
                      color: Color(0xFF63716B),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_feedbackNo != null)
                    _SuccessPanel(
                      feedbackNo: _feedbackNo!,
                      onReset: _reset,
                    )
                  else
                    _FeedbackForm(
                      contentController: _contentController,
                      contactController: _contactController,
                      apps: _apps,
                      selectedApp: _selectedApp,
                      switchingApp: _switchingApp,
                      submitting: _submitting,
                      uploadingImages: _uploadingImages,
                      attachmentNames: _attachmentNames,
                      error: _error,
                      onSubmit: _submit,
                      onPickImages: () => _imageInput?.click(),
                      onSelectApp: _selectApp,
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'Client ID: ${_sdk.clientId}\n'
                    'API: $_apiBaseUrl\n'
                    'Center: ${_selectedApp.centerId} / ${_selectedApp.sn}',
                    style: const TextStyle(
                      color: Color(0xFF83908A),
                      fontSize: 10,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF172923),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.camera,
            color: Color(0xFFDCEBE5),
            size: 22,
          ),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '反馈 SDK',
              style: TextStyle(
                color: Color(0xFF21342D),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'FLUTTER WEB DEMO',
              style: TextStyle(
                color: Color(0xFF7C8A84),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeedbackForm extends StatelessWidget {
  const _FeedbackForm({
    required this.contentController,
    required this.contactController,
    required this.apps,
    required this.selectedApp,
    required this.switchingApp,
    required this.submitting,
    required this.uploadingImages,
    required this.attachmentNames,
    required this.error,
    required this.onSubmit,
    required this.onPickImages,
    required this.onSelectApp,
  });

  final TextEditingController contentController;
  final TextEditingController contactController;
  final List<FeedbackApp> apps;
  final FeedbackApp selectedApp;
  final bool switchingApp;
  final bool submitting;
  final bool uploadingImages;
  final List<String> attachmentNames;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onPickImages;
  final ValueChanged<FeedbackApp> onSelectApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E0DD)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141E342B),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '问题出现在哪个软件',
            style: TextStyle(
              color: Color(0xFF4D5C65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          SegmentedButton<String>(
            segments: [
              for (final app in apps)
                ButtonSegment(value: app.key, label: Text(app.label)),
            ],
            selected: {selectedApp.key},
            onSelectionChanged: switchingApp
                ? null
                : (selection) {
                    final app = apps.firstWhere(
                      (item) => item.key == selection.first,
                    );
                    onSelectApp(app);
                  },
          ),
          const SizedBox(height: 18),
          const Text(
            '问题描述',
            style: TextStyle(
              color: Color(0xFF4D5C65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: contentController,
            minLines: 7,
            maxLines: 10,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: '描述操作步骤、遇到的问题和预期结果',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '联系方式',
            style: TextStyle(
              color: Color(0xFF4D5C65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: contactController,
            maxLength: 128,
            decoration: const InputDecoration(hintText: '手机号或邮箱'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: submitting || uploadingImages ? null : onPickImages,
            icon: uploadingImages
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(
              uploadingImages
                  ? '正在上传图片'
                  : attachmentNames.isEmpty
                      ? '添加图片附件'
                      : '继续添加图片',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          if (attachmentNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final name in attachmentNames)
                  Chip(
                    avatar: const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    label: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFBECEC),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFF8E3030),
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: submitting || uploadingImages || switchingApp
                ? null
                : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            label: Text(
              submitting
                  ? '正在提交'
                  : switchingApp
                      ? '正在切换'
                      : '提交反馈',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({
    required this.feedbackNo,
    required this.onReset,
  });

  final String feedbackNo;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E0DD)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 54,
            color: Color(0xFF0F766E),
          ),
          const SizedBox(height: 12),
          const Text(
            '反馈已提交',
            style: TextStyle(
              color: Color(0xFF1C3028),
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            feedbackNo,
            style: const TextStyle(
              color: Color(0xFF2A4940),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onReset,
            child: const Text('继续反馈'),
          ),
        ],
      ),
    );
  }
}
