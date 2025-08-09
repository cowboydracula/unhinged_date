// lib/services/geo.dart
import 'dart:math';

String fuzzGeohash(double lat, double lon) {
  // round to ~20km cells, then jitter ~2km
  final rlat = (lat * 10).roundToDouble() / 10; // ~11km per 0.1° lat
  final rlon = (lon * 10).roundToDouble() / 10;
  final j = Random();
  final jlat = rlat + (j.nextDouble() - 0.5) * 0.03;
  final jlon = rlon + (j.nextDouble() - 0.5) * 0.03;
  return '${jlat.toStringAsFixed(3)},${jlon.toStringAsFixed(3)}'; // coarse token
}
