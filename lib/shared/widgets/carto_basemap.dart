import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const cartoBaseTileUrlTemplate =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

String? cartoTileUrlTemplate(String key) {
  final value = key.trim();
  return value.isEmpty
      ? null
      : '$cartoBaseTileUrlTemplate?key=${Uri.encodeQueryComponent(value)}';
}

class CartoBasemapUnavailable implements Exception {
  const CartoBasemapUnavailable();

  @override
  String toString() => '배경 지도 요청 실패';
}

class CartoTileClient extends http.BaseClient {
  CartoTileClient(this._delegate, {this.onAuthenticationNotice});

  final http.Client _delegate;
  final VoidCallback? onAuthenticationNotice;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // Buffer once so body-stream errors cannot leak a keyed URI from http.
      // Bound the whole request/read; image decoding still happens only once.
      final response = await (() async {
        final stream = await _delegate.send(request);
        return http.Response.fromStream(stream);
      })().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CartoBasemapUnavailable();
      }
      // Observed CARTO authentication notice, 2026-10-15. Keep its image visible.
      // This tag can change; release QA must also inspect the real rendered map.
      if (response.headers['etag'] == '"wm-da89c20e77c1-light"') {
        onAuthenticationNotice?.call();
      }
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    } catch (_) {
      // flutter_map reports tile errors. Never pass through a URL or API key.
      throw const CartoBasemapUnavailable();
    }
  }

  @override
  void close() => _delegate.close();
}
