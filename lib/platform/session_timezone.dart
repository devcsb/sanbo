import 'dart:developer' as developer;

import 'package:flutter/services.dart';

const defaultSessionTimezone = 'Asia/Seoul';

/// Returns the device's IANA timezone for new sessions.
///
/// The stored value is used for minute buckets and daily summaries, so using
/// the native identifier is safer than Dart's short `timeZoneName` (which is
/// not an IANA database key). Tests and desktop builds use the product's
/// historical Korea fallback when no native channel is available.
Future<String> currentSessionTimezone() async {
  try {
    final timezone = await const MethodChannel(
      'sanbo/session_notifications',
    ).invokeMethod<String>('getTimezone').timeout(const Duration(seconds: 2));
    if (timezone != null && _looksLikeIanaTimezone(timezone)) {
      return timezone;
    }
  } on MissingPluginException {
    // Desktop, web, and widget tests do not install the native channel.
  } on PlatformException {
    // A timezone lookup must never prevent a walk from starting.
  } catch (e, st) {
    developer.log(
      'Timezone channel lookup failed',
      name: 'sanbo.session_timezone',
      error: e,
      stackTrace: st,
    );
  }
  return defaultSessionTimezone;
}

bool _looksLikeIanaTimezone(String value) {
  return value == 'UTC' || value.contains('/');
}
