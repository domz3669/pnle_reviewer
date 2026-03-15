import 'dart:io' show Platform;
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  static String? _cachedDeviceId;

  factory DeviceService() {
    return _instance;
  }

  DeviceService._internal();

  /// Get the persistent device ID.
  /// On Android: uses Settings.Secure.ANDROID_ID — the same ID that Niotron uses.
  /// This ID survives app uninstall, reinstall, and data clear.
  /// It only resets on factory reset.
  /// On iOS: uses identifierForVendor.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    try {
      if (Platform.isAndroid) {
        // Use ANDROID_ID (Settings.Secure.ANDROID_ID)
        // This is the same persistent ID that Niotron/Kodular apps use
        const androidIdPlugin = AndroidId();
        final String? androidId = await androidIdPlugin.getId();

        if (androidId != null && androidId.isNotEmpty) {
          _cachedDeviceId = androidId;
          return androidId;
        }
      } else if (Platform.isIOS) {
        // Use identifierForVendor on iOS
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        final iosId = iosInfo.identifierForVendor ?? 'unknown_ios';
        _cachedDeviceId = iosId;
        return iosId;
      }
    } catch (e) {
      // Plugin failed — fall through to fallback
    }

    // Final fallback (shouldn't reach here)
    _cachedDeviceId = 'unknown_device';
    return 'unknown_device';
  }

  /// Alias for getDeviceId — always returns the same persistent ID.
  Future<String> getDeviceFingerprint() async {
    return getDeviceId();
  }

  /// Clear cached device ID (for testing)
  void clearCache() {
    _cachedDeviceId = null;
  }
}
