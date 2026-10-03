import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// A random per-install identifier kept in the Android Keystore / iOS
/// Keychain. The backend binds each student account to one device ID so a
/// single paid login cannot be shared across many phones.
class DeviceId {
  DeviceId._();

  static const _key = 'device_install_id';
  static const _storage = FlutterSecureStorage();
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    var id = await _storage.read(key: _key);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _key, value: id);
    }
    return _cached = id;
  }
}
