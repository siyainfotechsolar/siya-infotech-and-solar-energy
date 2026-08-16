import 'dart:typed_data';

class ExifMetadata {
  final double? latitude;
  final double? longitude;
  final String? dateTimeOriginal;
  final bool hasGps;

  ExifMetadata({
    this.latitude,
    this.longitude,
    this.dateTimeOriginal,
  }) : hasGps = latitude != null && longitude != null;
}

class ExifHelper {
  /// Extract EXIF GPS and DateTimeOriginal from image bytes (JPEG)
  static ExifMetadata extractExif(Uint8List bytes) {
    try {
      if (bytes.length < 12 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        // Not a standard JPEG
        return ExifMetadata();
      }

      int offset = 2;
      while (offset < bytes.length - 4) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }

        final marker = bytes[offset + 1];
        if (marker == 0xE1) {
          // APP1 Marker
          final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
          final app1Bytes = bytes.sublist(offset + 4, offset + 2 + length);
          return _parseApp1(app1Bytes);
        }

        if (marker == 0xD9 || marker == 0xDA) {
          break; // SOS or EOI
        }

        final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
        offset += 2 + length;
      }
    } catch (_) {}

    return ExifMetadata();
  }

  static ExifMetadata _parseApp1(Uint8List data) {
    if (data.length < 14) return ExifMetadata();

    // Check "Exif\0\0" header
    if (data[0] != 0x45 || data[1] != 0x78 || data[2] != 0x69 || data[3] != 0x66) {
      return ExifMetadata();
    }

    final tiffOffset = 6;
    final isLittleEndian = data[tiffOffset] == 0x49 && data[tiffOffset + 1] == 0x49;

    int read16(int p) {
      if (p + 1 >= data.length) return 0;
      return isLittleEndian
          ? (data[p] | (data[p + 1] << 8))
          : ((data[p] << 8) | data[p + 1]);
    }

    int read32(int p) {
      if (p + 3 >= data.length) return 0;
      return isLittleEndian
          ? (data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24))
          : ((data[p] << 24) | (data[p + 1] << 16) | (data[p + 2] << 8) | data[p + 3]);
    }

    double readRational(int p) {
      final num = read32(p);
      final den = read32(p + 4);
      if (den == 0) return 0.0;
      return num / den;
    }

    final firstIfdOffset = tiffOffset + read32(tiffOffset + 4);
    if (firstIfdOffset >= data.length) return ExifMetadata();

    int gpsIfdOffset = 0;
    String? dateTime;

    // Read IFD0
    final numEntries = read16(firstIfdOffset);
    for (int i = 0; i < numEntries; i++) {
      final entryOffset = firstIfdOffset + 2 + i * 12;
      if (entryOffset + 12 > data.length) break;

      final tag = read16(entryOffset);
      final valOffset = read32(entryOffset + 8);

      if (tag == 0x8825) {
        // GPSInfo Tag
        gpsIfdOffset = tiffOffset + valOffset;
      } else if (tag == 0x0132 || tag == 0x9003) {
        // DateTime or DateTimeOriginal
        final strOffset = tiffOffset + valOffset;
        if (strOffset < data.length) {
          final strBytes = data.sublist(strOffset, (strOffset + 20).clamp(0, data.length));
          final str = String.fromCharCodes(strBytes).split('\x00').first.trim();
          if (str.isNotEmpty) dateTime = str;
        }
      }
    }

    if (gpsIfdOffset == 0 || gpsIfdOffset >= data.length) {
      return ExifMetadata(dateTimeOriginal: dateTime);
    }

    // Read GPS IFD
    final gpsEntries = read16(gpsIfdOffset);
    String latRef = 'N';
    String lngRef = 'E';
    double? latDeg, latMin, latSec;
    double? lngDeg, lngMin, lngSec;

    for (int i = 0; i < gpsEntries; i++) {
      final entryOffset = gpsIfdOffset + 2 + i * 12;
      if (entryOffset + 12 > data.length) break;

      final tag = read16(entryOffset);
      final valOffset = read32(entryOffset + 8);

      if (tag == 0x0001) {
        // GPSLatitudeRef
        latRef = String.fromCharCode(data[entryOffset + 8]);
      } else if (tag == 0x0002) {
        // GPSLatitude
        final p = tiffOffset + valOffset;
        latDeg = readRational(p);
        latMin = readRational(p + 8);
        latSec = readRational(p + 16);
      } else if (tag == 0x0003) {
        // GPSLongitudeRef
        lngRef = String.fromCharCode(data[entryOffset + 8]);
      } else if (tag == 0x0004) {
        // GPSLongitude
        final p = tiffOffset + valOffset;
        lngDeg = readRational(p);
        lngMin = readRational(p + 8);
        lngSec = readRational(p + 16);
      }
    }

    double? latitude;
    double? longitude;

    if (latDeg != null && latMin != null && latSec != null) {
      latitude = latDeg + (latMin / 60.0) + (latSec / 3600.0);
      if (latRef.toUpperCase() == 'S') latitude = -latitude;
    }

    if (lngDeg != null && lngMin != null && lngSec != null) {
      longitude = lngDeg + (lngMin / 60.0) + (lngSec / 3600.0);
      if (lngRef.toUpperCase() == 'W') longitude = -longitude;
    }

    return ExifMetadata(
      latitude: latitude,
      longitude: longitude,
      dateTimeOriginal: dateTime,
    );
  }
}
