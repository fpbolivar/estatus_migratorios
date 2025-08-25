import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CookieManager {
  static final CookieManager _instance = CookieManager._internal();
  final _storage = const FlutterSecureStorage();

  factory CookieManager() {
    return _instance;
  }

  CookieManager._internal();

  Future<void> saveCookies(String? cookies) async {
    if (cookies != null && cookies.isNotEmpty) {
      await _storage.write(key: 'session_cookies', value: cookies);
    }
  }

  Future<String?> getCookies() async {
    return await _storage.read(key: 'session_cookies');
  }

  Future<void> clearCookies() async {
    await _storage.delete(key: 'session_cookies');
  }
}