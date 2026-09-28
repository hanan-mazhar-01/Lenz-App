import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:replica_detector/services/image_origin.dart';

void main() {
  img.Image picture() => img.Image(width: 16, height: 16);

  test('an ordinary camera photo gives no hint', () {
    final im = picture()
      ..exif.imageIfd.make = 'vivo'
      ..exif.imageIfd.model = 'V2043';
    expect(ImageOrigin.hint(img.encodeJpg(im)), isNull);
  });

  test('no camera information or an editing tool is a hint, never a verdict', () {
    expect(ImageOrigin.hint(img.encodeJpg(picture())), contains('no camera information'));
    final edited = picture()
      ..exif.imageIfd.make = 'SONY'
      ..exif.imageIfd.data[0x0131] = img.IfdValueAscii('Adobe Photoshop Lightroom Classic 15.5.1 (Macintosh)');
    expect(ImageOrigin.hint(img.encodeJpg(edited)), contains('Adobe Photoshop Lightroom Classic'));
    expect(ImageOrigin.hint(img.encodePng(picture())), contains('not a camera JPEG'));
  });
}
