import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/profile/domain/car_photo_storage.dart';

/// After Save swaps saved originals for blurred copies, only the owner's own
/// files that none of their cars still uses may be deleted.
void main() {
  const bucket = 'https://proj.supabase.co/storage/v1/object/public/car-photos/';
  const me = '11111111-1111-1111-1111-111111111111';
  const them = '22222222-2222-2222-2222-222222222222';
  String url(String path) => '$bucket$path';

  List<String> stale({List<String> replaced = const [], List<String> referenced = const [], List<String> cutouts = const []}) =>
      stalePhotoPaths(ownerId: me, bucketUrl: bucket, replaced: replaced, referenced: referenced, staleCutouts: cutouts);

  test('a replaced original goes with its thumbnail and cut-out', () {
    expect(stale(replaced: [url('$me/1700_0.jpg')], referenced: [url('$me/1800_0_pb.jpg')]), [
      '$me/1700_0.jpg',
      '$me/1700_0_t.jpg',
      '$me/1700_0_cut.png',
    ]);
  });

  test('a photo another car of theirs still shows is kept, with its thumbnail and cut-out', () {
    expect(stale(replaced: [url('$me/1700_0.jpg')], referenced: [url('$me/1700_0.jpg'), url('$me/1800_0_pb.jpg')]), isEmpty);
  });

  test('the same file spelled another way still counts as in use', () {
    expect(stale(replaced: [url('$me/my%20car.jpg')], referenced: [url('$me/my car.jpg')]), isEmpty);
    expect(stale(replaced: [url('$me/a.jpg')], referenced: [url('$me/a.jpg?v=3')]), isEmpty);
  });

  test('a cut-out a car still uses is not deleted with its photo', () {
    expect(stale(replaced: [url('$me/a.jpg')], referenced: [url('$me/a_cut.png')]), ['$me/a.jpg', '$me/a_t.jpg']);
  });

  test('never anyone else\'s files, another bucket, another host, or odd paths', () {
    expect(
      stale(replaced: [
        url('$them/a.jpg'), // someone else's folder
        'https://proj.supabase.co/storage/v1/object/public/post-photos/$me/a.jpg', // another bucket
        'https://evil.example.com/storage/v1/object/public/car-photos/$me/a.jpg', // another host
        url('$me/a.jpg?v=2'), // overwritten in place
        url('$me/../$them/a.jpg'), // climbing out of the folder
        url('$me%2F..%2F$them%2Fa.jpg'), // the same, encoded
        url('$me//a.jpg'),
        url(me), // the folder itself
        url('a.jpg'),
        'assets/cars/myvi.png',
        '',
      ]),
      isEmpty,
    );
  });

  test('nested files in their own folder are fine', () {
    expect(stale(replaced: [url('$me/mods/1.jpg')]), ['$me/mods/1.jpg', '$me/mods/1_t.jpg', '$me/mods/1_cut.png']);
  });

  test('a stale cut-out under its own name goes, unless a car uses it', () {
    expect(stale(cutouts: [url('$me/cutouts/car.png')]), ['$me/cutouts/car.png']);
    expect(stale(cutouts: [url('$me/cutouts/car.png')], referenced: [url('$me/cutouts/car.png')]), isEmpty);
    expect(stale(cutouts: [url('$them/cutouts/car.png')]), isEmpty);
  });

  test('each path once', () {
    expect(stale(replaced: [url('$me/a.jpg'), url('$me/a.jpg')], cutouts: [url('$me/a_cut.png')]), ['$me/a.jpg', '$me/a_t.jpg', '$me/a_cut.png']);
  });

  test('nothing replaced, nothing deleted', () {
    expect(stale(referenced: [url('$me/a.jpg')]), isEmpty);
  });

  test('ownedPhotoPath', () {
    expect(ownedPhotoPath(url('$me/a.jpg'), bucketUrl: bucket, ownerId: me), '$me/a.jpg');
    expect(ownedPhotoPath(url('$me/a.jpg'), bucketUrl: bucket.substring(0, bucket.length - 1), ownerId: me), '$me/a.jpg');
    expect(ownedPhotoPath(url('$me/a.jpg'), bucketUrl: bucket, ownerId: ''), isNull);
    expect(ownedPhotoPath(url('$me/a.jpg'), bucketUrl: '', ownerId: me), isNull);
  });

  test('blurred photos are recognised by name', () {
    expect(isPlateBlurredUrl(url('$me/1700_0_pb.jpg')), isTrue);
    expect(isPlateBlurredUrl(url('$me/1700_0_pb.png')), isTrue);
    expect(isPlateBlurredUrl(url('$me/1700_0.jpg')), isFalse);
    expect(isPlateBlurredUrl(url('$me/1700_0.png')), isFalse); // 0.3.44 PNGs don't say
    expect(isPlateBlurredUrl(url('$me/pb/1700_0.jpg')), isFalse);
    expect(isPlateBlurredUrl(url('$me/1700_0_pb.jpg?v=2')), isTrue);
  });
}
