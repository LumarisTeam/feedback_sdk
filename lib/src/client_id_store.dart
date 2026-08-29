import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 匿名身份存储。
///
/// 规则（对齐后端 PRD 第 5 节）：
/// - 首次启动生成 UUID 并持久化；
/// - 卸载重装后允许变化；
/// - 绝不每次请求重新生成。
class ClientIdStore {
  static const _key = 'feedback_client_id';
  final _uuid = const Uuid();

  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await prefs.setString(_key, id);
    return id;
  }
}
