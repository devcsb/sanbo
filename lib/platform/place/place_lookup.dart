import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

class PlaceLookupResult {
  const PlaceLookupResult({required this.suggestedName, required this.address});

  final String suggestedName;
  final String address;
}

abstract interface class PlaceLookup {
  Future<PlaceLookupResult?> lookup({
    required double latitude,
    required double longitude,
  });
}

/// Uses the operating system's geocoding service only after an explicit user
/// action. The app does not batch coordinates or call a public OSM geocoder.
class DevicePlaceLookup implements PlaceLookup {
  const DevicePlaceLookup();

  @override
  Future<PlaceLookupResult?> lookup({
    required double latitude,
    required double longitude,
  }) async {
    final placemarks = await Geocoding(locale: const Locale('ko', 'KR'))
        .placemarkFromCoordinates(latitude, longitude)
        .timeout(const Duration(seconds: 6));
    if (placemarks.isEmpty) return null;
    return placeLookupResultFromPlacemark(placemarks.first);
  }
}

PlaceLookupResult? placeLookupResultFromPlacemark(Placemark placemark) {
  final nameCandidates = [
    placemark.name,
    placemark.street,
    placemark.subLocality,
    placemark.locality,
  ];
  final suggestedName = nameCandidates
      .map((value) => value?.trim() ?? '')
      .firstWhere(
        (value) => value.isNotEmpty && !_looksLikeCoordinate(value),
        orElse: () => '',
      );

  final addressParts = <String>[];
  for (final value in [
    placemark.administrativeArea,
    placemark.locality,
    placemark.subLocality,
    placemark.street,
  ]) {
    final part = value?.trim() ?? '';
    if (part.isNotEmpty && !addressParts.contains(part)) {
      addressParts.add(part);
    }
  }
  final address = addressParts.join(' ');
  if (suggestedName.isEmpty && address.isEmpty) return null;

  return PlaceLookupResult(
    suggestedName: suggestedName.isNotEmpty ? suggestedName : address,
    address: address,
  );
}

bool _looksLikeCoordinate(String value) {
  return RegExp(
    r'^-?\d{1,3}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?$',
  ).hasMatch(value);
}

final placeLookupProvider = Provider<PlaceLookup>(
  (ref) => const DevicePlaceLookup(),
);
