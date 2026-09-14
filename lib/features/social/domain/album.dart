/// A named set of moments on a profile (row from `moment_albums_with_counts`).
class MomentAlbum {
  const MomentAlbum({required this.id, required this.ownerId, required this.name, this.coverUrl, required this.count, required this.createdAt});
  final String id;
  final String ownerId;
  final String name;
  final String? coverUrl;
  final int count;
  final DateTime createdAt;

  factory MomentAlbum.fromMap(Map<String, dynamic> m) => MomentAlbum(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        name: m['name'] as String,
        coverUrl: m['cover_url'] as String?,
        count: (m['item_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
