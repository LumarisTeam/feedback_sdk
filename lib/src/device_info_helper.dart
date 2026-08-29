import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 自动采集环境信息，用于填充提交反馈时的 `extra` 字段。
///
/// 采集内容：app_version / app_build / platform / os_version / device_model / page。
/// 注意：`app_name` 不在这里采集（它由 `FeedbackConfig.appName` 决定，用于区分产品线）。
class DeviceInfoHelper {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<Map<String, dynamic>> collect({String? page}) async {
    final map = <String, dynamic>{};

    try {
      final pkg = await PackageInfo.fromPlatform();
      map['app_version'] = pkg.version;
      map['app_build'] = pkg.buildNumber;
    } catch (_) {
      // 采集失败不影响反馈提交
    }

    map['platform'] = defaultTargetPlatform.name.toLowerCase();

    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final d = await _deviceInfo.androidInfo;
          map['os_version'] = 'Android ${d.version.release}';
          map['device_model'] = d.model;
          break;
        case TargetPlatform.iOS:
          final d = await _deviceInfo.iosInfo;
          map['os_version'] = 'iOS ${d.systemVersion}';
          map['device_model'] = d.model;
          break;
        case TargetPlatform.macOS:
          final d = await _deviceInfo.macOsInfo;
          map['os_version'] = 'macOS ${d.osRelease}';
          map['device_model'] = d.model;
          break;
        case TargetPlatform.windows:
          final d = await _deviceInfo.windowsInfo;
          map['os_version'] = d.productName;
          map['device_model'] = d.computerName;
          break;
        case TargetPlatform.linux:
          final d = await _deviceInfo.linuxInfo;
          map['os_version'] = d.versionId ?? 'Linux';
          map['device_model'] = d.machineId ?? 'unknown';
          break;
        case TargetPlatform.fuchsia:
          break;
      }
    } catch (_) {
      // 采集失败不影响反馈提交
    }

    if (page != null) map['page'] = page;
    return map;
  }
}
