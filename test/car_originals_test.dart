import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/profile/domain/car_photo_storage.dart';

/// Undo the plate blur: what Save does with each photo, where originals are
/// kept, and which private originals a save or delete may remove.
void main() {
  const bucket = 'https://proj.supabase.co/storage/v1/object/public/car-photos/';
  const me = '11111111-1111-1111-1111-111111111111';
  const them = '22222222-2222-2222-2222-222222222222';
  String url(String path) => '$bucket$path';
  final picked = Uint8List.fromList([1, 2, 3]);
  final blurred = Uint8List.fromList([4, 5, 6]);
  final kept = Uint8List.fromList([7, 8, 9]);

  group('planCarPhoto', () {
    test('a new photo, switch on: the blurred copy goes up and the original is kept', () {
      final s = planCarPhoto(url: null, hidePlate: true, original: picked, blurred: blurred);
      expect(s.bytes, blurred);
      expect(s.plateBlurred, isTrue);
      expect(s.original, picked);
      expect(s.keptOriginal, isNull);
      expect(s.replaces, isNull);
    });

    test('a new photo, switch off: goes up as picked, nothing kept', () {
      final s = planCarPhoto(url: null, hidePlate: false, original: picked, blurred: blurred);
      expect(s.bytes, picked);
      expect(s.plateBlurred, isFalse);
      expect(s.original, isNull);
    });

    test('a saved photo blurred now: replaces the public one, its original moves to the private bucket', () {
      final s = planCarPhoto(url: url('$me/1700_0.jpg'), hidePlate: true, original: picked, blurred: blurred);
      expect(s.bytes, blurred);
      expect(s.replaces, url('$me/1700_0.jpg'));
      expect(s.original, picked);
      expect(s.restoresOriginal, isFalse);
    });

    test('a saved blurred photo stays as it is, switch on or off', () {
      for (final on in [true, false]) {
        final s = planCarPhoto(url: url('$me/1800_0_pb.jpg'), hidePlate: on, originalPath: '$me/1800_0.jpg');
        expect(s.url, url('$me/1800_0_pb.jpg'), reason: 'switch $on');
        expect(s.bytes, isNull);
      }
    });

    test('Show original with no blur: the original goes back up in place of the blurred copy', () {
      for (final on in [true, false]) {
        final s = planCarPhoto(url: url('$me/1800_0_pb.jpg'), hidePlate: on, original: kept, restored: true, originalPath: '$me/1800_0.jpg');
        expect(s.bytes, kept, reason: 'switch $on');
        expect(s.plateBlurred, isFalse);
        expect(s.replaces, url('$me/1800_0_pb.jpg'));
        expect(s.restoresOriginal, isTrue);
        expect(s.original, isNull, reason: 'nothing new to keep');
      }
    });

    test('a new blur on a shown original reuses the kept original', () {
      final s = planCarPhoto(url: url('$me/1800_0_pb.jpg'), hidePlate: true, original: kept, blurred: blurred, restored: true, originalPath: '$me/1800_0.jpg');
      expect(s.bytes, blurred);
      expect(s.plateBlurred, isTrue);
      expect(s.keptOriginal, '$me/1800_0.jpg');
      expect(s.original, isNull);
    });

    test('more blur on top of a blurred copy keeps pointing at the true original', () {
      final s = planCarPhoto(url: url('$me/1800_0_pb.jpg'), hidePlate: true, original: blurred, blurred: Uint8List.fromList([0]), originalPath: '$me/1800_0.jpg');
      expect(s.keptOriginal, '$me/1800_0.jpg');
      expect(s.original, isNull, reason: 'the blurred copy must not be stored as the "original"');
    });

    test('a photo blurred before 2 Oct has no original: blurring it more keeps what was there', () {
      final s = planCarPhoto(url: url('$me/1600_0_pb.jpg'), hidePlate: true, original: blurred, blurred: Uint8List.fromList([0]));
      expect(s.original, blurred);
      expect(s.keptOriginal, isNull);
    });
  });

  group('originalPathFor', () {
    test('a saved photo of theirs keeps its file name', () {
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_0_pb.jpg', replacedPath: '$me/1700_0.jpg', ext: 'jpg'), '$me/1700_0.jpg');
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_0_pb.jpg', replacedPath: '$me/1700_0.png', ext: 'png'), '$me/1700_0.png');
    });

    test('a new photo takes the blurred name without _pb, with its own extension', () {
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_2_pb.jpg', ext: 'jpg'), '$me/1900_2.jpg');
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_2_pb.jpg', ext: 'png'), '$me/1900_2.png');
    });

    test('a photo from elsewhere or someone else\'s folder is named after the blurred copy, in their own folder', () {
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_0_pb.jpg', replacedPath: '$them/1700_0.jpg', ext: 'jpg'), '$me/1900_0.jpg');
      expect(originalPathFor(ownerId: me, blurredPath: '$me/1900_0_pb.jpg', replacedPath: '$me/../$them/a.jpg', ext: 'jpg'), '$me/1900_0.jpg');
    });
  });

  group('nextPhotoOriginals', () {
    test('a blurred upload is mapped to its original', () {
      final r = nextPhotoOriginals(ownerId: me, before: const {}, photoUrls: [url('$me/1900_0_pb.jpg')], added: {url('$me/1900_0_pb.jpg'): '$me/1900_0.jpg'});
      expect(r.originals, {url('$me/1900_0_pb.jpg'): '$me/1900_0.jpg'});
      expect(r.dropped, isEmpty);
    });

    test('Show original: the entry goes, and so does the private file', () {
      final r = nextPhotoOriginals(
        ownerId: me,
        before: {url('$me/1900_0_pb.jpg'): '$me/1900_0.jpg', url('$me/1900_1_pb.jpg'): '$me/1900_1.jpg'},
        photoUrls: [url('$me/2000_0.jpg'), url('$me/1900_1_pb.jpg')],
      );
      expect(r.originals, {url('$me/1900_1_pb.jpg'): '$me/1900_1.jpg'});
      expect(r.dropped, ['$me/1900_0.jpg']);
    });

    test('a re-blur keeps the private file under the new URL', () {
      final r = nextPhotoOriginals(
        ownerId: me,
        before: {url('$me/1900_0_pb.jpg'): '$me/1900_0.jpg'},
        photoUrls: [url('$me/2000_0_pb.jpg')],
        added: {url('$me/2000_0_pb.jpg'): '$me/1900_0.jpg'},
      );
      expect(r.originals, {url('$me/2000_0_pb.jpg'): '$me/1900_0.jpg'});
      expect(r.dropped, isEmpty);
    });

    test('a removed photo takes its original with it', () {
      final r = nextPhotoOriginals(ownerId: me, before: {url('$me/1900_0_pb.jpg'): '$me/1900_0.jpg'}, photoUrls: const []);
      expect(r.originals, isEmpty);
      expect(r.dropped, ['$me/1900_0.jpg']);
    });

    test('photos without an entry (blurred before 2 Oct, or plain) stay without one', () {
      final r = nextPhotoOriginals(ownerId: me, before: const {}, photoUrls: [url('$me/1600_0_pb.jpg'), url('$me/1700_0.jpg')]);
      expect(r.originals, isEmpty);
      expect(r.dropped, isEmpty);
    });

    test('never maps to, or drops, someone else\'s path', () {
      final r = nextPhotoOriginals(
        ownerId: me,
        before: {url('$me/a_pb.jpg'): '$them/a.jpg', url('$me/b_pb.jpg'): '$me/../$them/b.jpg'},
        photoUrls: [url('$me/c_pb.jpg')],
        added: {url('$me/c_pb.jpg'): '$them/c.jpg'},
      );
      expect(r.originals, isEmpty);
      expect(r.dropped, isEmpty);
    });
  });

  group('staleOriginalPaths', () {
    test('only their own, and not while another car still maps to it', () {
      expect(
        staleOriginalPaths(ownerId: me, candidates: ['$me/a.jpg', '$me/b.jpg', '$them/c.jpg', '$me/a.jpg', 'x.jpg', '$me/../$them/d.jpg'], referenced: ['$me/b.jpg']),
        ['$me/a.jpg'],
      );
    });
  });

  group('parsePhotoOriginals', () {
    test('reads a JSON object of strings, ignores anything else', () {
      expect(parsePhotoOriginals({'u': 'p', 'n': 3, 'x': null}), {'u': 'p'});
      expect(parsePhotoOriginals(null), isEmpty);
      expect(parsePhotoOriginals('nope'), isEmpty);
      expect(parsePhotoOriginals(const []), isEmpty);
    });
  });
}
