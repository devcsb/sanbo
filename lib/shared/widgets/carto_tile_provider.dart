import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'carto_basemap.dart';

/// Uses flutter_map's renderer/cache without putting keyed URLs in diagnostics.
class CartoTileProvider extends TileProvider {
  CartoTileProvider(http.Client client, {required this.onUnavailable}) {
    _client = CartoTileClient(
      client,
      onAuthenticationNotice: () {
        _authenticationNotice = true;
        onUnavailable();
      },
    );
  }

  final VoidCallback onUnavailable;
  late final CartoTileClient _client;
  int _active = 0;
  bool _disposing = false;
  bool _authenticationNotice = false;
  final _disposed = Completer<void>();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _CartoTileImage(getTileUrl(coordinates, options), this);

  Future<ui.Codec> _load(
    _CartoTileImage key,
    ImageDecoderCallback decode,
  ) async {
    var evict = false;
    _active++;
    try {
      if (_disposing) {
        evict = true;
        return await _transparent(decode);
      }
      final bytes = await _client.readBytes(
        Uri.parse(key._url),
        headers: headers,
      );
      evict = _authenticationNotice;
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      evict = true;
      // NetworkTileProvider diagnostics include its original keyed URL even
      // for sanitized exceptions. Report status and resolve a safe image.
      onUnavailable();
      return await _transparent(decode);
    } finally {
      // Do not cache a transparent failure (or authentication notice) as a
      // successful map. Reopening the screen must be able to recover.
      if (evict) {
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      }
      _active--;
      _closeIfIdle();
    }
  }

  Future<ui.Codec> _transparent(ImageDecoderCallback decode) async => decode(
    await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage),
  );

  void _closeIfIdle() {
    if (_disposing && _active == 0 && !_disposed.isCompleted) {
      _client.close();
      _disposed.complete();
    }
  }

  @override
  Future<void> dispose() {
    _disposing = true;
    _closeIfIdle();
    return _disposed.future;
  }
}

@immutable
class _CartoTileImage extends ImageProvider<_CartoTileImage> {
  const _CartoTileImage(this._url, this._provider);

  final String _url;
  final CartoTileProvider _provider;

  @override
  SynchronousFuture<_CartoTileImage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CartoTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _provider._load(key, decode),
    scale: 1,
    debugLabel: 'CARTO background tile',
  );

  @override
  bool operator ==(Object other) =>
      other is _CartoTileImage && other._url == _url;

  @override
  int get hashCode => _url.hashCode;
}
