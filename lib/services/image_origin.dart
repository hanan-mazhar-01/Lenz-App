import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What the image file itself says about where it came from. Only a hint
/// for Gemini's "is this a real photo of the item?" decision, never a
/// verdict on its own: messaging apps and the anonymous-scanning setting
/// also remove camera information.
abstract final class ImageOrigin {
  static final RegExp _editors = RegExp(
    r'photoshop|lightroom|gimp|canva|capture one|affinity|pixelmator|illustrator|picsart|figma|blender|cinema 4d|keyshot',
    caseSensitive: false,
  );

  /// A one-sentence hint, or null when the file looks like an ordinary
  /// camera photo.
  static String? hint(Uint8List bytes) {
    final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isJpeg) {
      return 'The file is not a camera JPEG (typical of screenshots and of images saved from websites).';
    }
    img.ExifData? exif;
    try {
      exif = img.decodeJpgExif(bytes);
    } catch (_) {
      exif = null;
    }
    final ifd = exif?.imageIfd;
    final make = ifd?.make?.trim() ?? '';
    final software = ifd?.data[0x0131]?.toString().trim() ?? '';
    if (software.isNotEmpty && _editors.hasMatch(software)) {
      return 'The file was edited in ${software.split('(').first.trim()}, as professional product and marketing photos are.';
    }
    if (make.isEmpty) {
      return 'The file has no camera information (normal for screenshots and for images saved from websites or messaging apps).';
    }
    return null;
  }
}
