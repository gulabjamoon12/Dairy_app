import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for sending SMS directly using platform channels
class SmsService {
  static const MethodChannel _channel = MethodChannel('com.example.gg/sms');

  /// Send SMS directly (Android only)
  /// Returns true if sent successfully, false otherwise
  static Future<bool> sendSms(String phoneNumber, String message) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'sendSms',
        {
          'phoneNumber': phoneNumber,
          'message': message,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error sending SMS: $e');
      return false;
    }
  }

  /// Check if SMS sending is supported
  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
