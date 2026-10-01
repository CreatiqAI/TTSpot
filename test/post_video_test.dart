import 'package:car_meet/core/config/media.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/domain/post_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mb = 1024 * 1024;

  group('postVideoProblem', () {
    test('a normal clip is fine', () {
      expect(postVideoProblem(bytes: 12 * mb, length: const Duration(seconds: 42)), isNull);
    });

    test('size is checked before the length is known', () {
      expect(postVideoProblem(bytes: 12 * mb), isNull);
      expect(postVideoProblem(bytes: 51 * mb), contains('50 MB'));
    });

    test('exactly 50 MB fits (the bucket cap), one byte more does not', () {
      expect(postVideoProblem(bytes: kPostVideoMaxMb * mb), isNull);
      expect(postVideoProblem(bytes: kPostVideoMaxMb * mb + 1), isNotNull);
    });

    test('up to 60 s; a clip that rounds to 1:00 still fits', () {
      expect(postVideoProblem(bytes: mb, length: const Duration(seconds: 60)), isNull);
      expect(postVideoProblem(bytes: mb, length: const Duration(milliseconds: 60400)), isNull);
      expect(postVideoProblem(bytes: mb, length: const Duration(milliseconds: 60600)), contains('60 seconds'));
      expect(postVideoProblem(bytes: mb, length: const Duration(minutes: 3)), contains('60 seconds'));
    });

    test('an empty file is refused', () {
      expect(postVideoProblem(bytes: 0), isNotNull);
    });
  });

  test('postVideoFormat: iPhone .mov stays QuickTime, the rest go up as MP4', () {
    expect(postVideoFormat('/tmp/IMG_0001.MOV'), (ext: 'mov', contentType: 'video/quicktime'));
    expect(postVideoFormat('/data/user/0/cache/clip.mp4'), (ext: 'mp4', contentType: 'video/mp4'));
    expect(postVideoFormat('/data/user/0/cache/clip.3gp'), (ext: 'mp4', contentType: 'video/mp4'));
  });

  group('Post with a video', () {
    Map<String, dynamic> row({Map<String, dynamic> extra = const {}}) => {
          'id': 'p1',
          'author_id': 'u1',
          'kind': 'post',
          'photo_urls': ['https://x/storage/v1/object/public/post-photos/u1/posts/1.jpg'],
          'cover_aspect': 0.5625,
          'created_at': '2026-10-02T10:00:00Z',
          ...extra,
        };

    test('reads the video columns; the poster is also the cover', () {
      final p = Post.fromMap(row(extra: {
        'video_url': 'https://x/storage/v1/object/public/post-photos/u1/posts/1.mp4',
        'video_poster_url': 'https://x/storage/v1/object/public/post-photos/u1/posts/1.jpg',
        'video_ms': 42000,
      }));
      expect(p.isVideo, isTrue);
      expect(p.videoMs, 42000);
      expect(p.cover, endsWith('/1.jpg'));
      expect(p.videoPoster, endsWith('/1.jpg'));
    });

    test('a photo post is not a video', () {
      final p = Post.fromMap(row());
      expect(p.isVideo, isFalse);
      expect(p.videoPoster, endsWith('/1.jpg'));
    });

    test('a video row without photo_urls still has a cover', () {
      final p = Post.fromMap(row(extra: {'photo_urls': <String>[], 'video_url': 'v.mp4', 'video_poster_url': 'v.jpg'}));
      expect(p.cover, 'v.jpg');
    });

    test('a place from the search is read back with its name', () {
      final p = Post.fromMap(row(extra: {'place_name': 'Mamak Sri Melur', 'place_address': 'Jalan Datuk Sulaiman, TTDI', 'lat': 3.14, 'lng': 101.63}));
      expect(p.place, isNull);
      expect(p.placeLabel, 'Mamak Sri Melur');
      expect(p.latLng, isNotNull);
    });
  });
}
