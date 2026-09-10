import 'package:flutter/services.dart';
import 'package:luci_mobile/utils/logger.dart';

class NotificationService {
  static const MethodChannel _channel = MethodChannel('com.openwrt.studio/notifications');

  /// Displays a native Android notification with high priority
  static Future<bool> showNotification({
    required int id,
    required String title,
    required String message,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('showNotification', {
        'id': id,
        'title': title,
        'message': message,
      });
      return res ?? false;
    } catch (e) {
      Logger.error('Failed to show native notification: $e');
      return false;
    }
  }

  /// Cancels an active notification or all notifications
  static Future<void> cancelNotification([int? id]) async {
    try {
      await _channel.invokeMethod('cancelNotification', {
        if (id != null) 'id': id,
      });
    } catch (e) {
      Logger.error('Failed to cancel notification: $e');
    }
  }
}
