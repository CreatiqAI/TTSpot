import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../domain/titi_message.dart';

/// One event of TiTi's answer stream (supabase/functions/titi).
sealed class TitiEvent {
  const TitiEvent();

  static TitiEvent? parse(String data) {
    final Object? j;
    try {
      j = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (j is! Map) return null;
    return switch (j['t']) {
      'session' => switch (j['id']) { final String id => TitiSessionStarted(id), _ => null },
      'delta' => TitiDelta(j['text'] as String? ?? ''),
      'break' => const TitiBreak(),
      'card' => switch (TitiCard.fromMap(j)) { final TitiCard c => TitiCardEvent(c), null => null },
      'action' => switch (TitiAction.fromMap(j)) { final TitiAction a => TitiActionEvent(a), null => null },
      'chips' => TitiChips([for (final o in (j['options'] as List? ?? const [])) if (o is String && o.trim().isNotEmpty) o.trim()]),
      'status' => TitiStatus(j['text'] as String? ?? '', j['tool'] as String?),
      'error' => TitiError(j['text'] as String? ?? 'My radio cut out. Try again?'),
      'done' => TitiDone(id: j['id'] as String?, title: j['title'] as String?),
      _ => null,
    };
  }
}

/// A new chat was started for this question; its id.
class TitiSessionStarted extends TitiEvent {
  const TitiSessionStarted(this.id);
  final String id;
}

class TitiDelta extends TitiEvent {
  const TitiDelta(this.text);
  final String text;
}

class TitiBreak extends TitiEvent {
  const TitiBreak();
}

class TitiCardEvent extends TitiEvent {
  const TitiCardEvent(this.card);
  final TitiCard card;
}

class TitiActionEvent extends TitiEvent {
  const TitiActionEvent(this.action);
  final TitiAction action;
}

class TitiChips extends TitiEvent {
  const TitiChips(this.options);
  final List<String> options;
}

/// A tool is running ("Checking meets near you…"); [tool] picks TiTi's pose.
class TitiStatus extends TitiEvent {
  const TitiStatus(this.text, this.tool);
  final String text;
  final String? tool;
}

class TitiError extends TitiEvent {
  const TitiError(this.text);
  final String text;
}

/// The end. [id]: the saved answer's row; [title]: a new chat's name.
class TitiDone extends TitiEvent {
  const TitiDone({this.id, this.title});
  final String? id;
  final String? title;
}

/// The chats with TiTi: the answer stream from the `titi` function, the saved
/// chats (`titi_sessions`) and their messages (`titi_messages`), and my photos
/// in the private `titi-uploads` bucket. RLS: my own rows and files only.
class TitiRepository {
  TitiRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'titi-uploads';

  /// Streams one answer, token by token. Cancelling the subscription closes
  /// the connection, which stops the model on the server too.
  ///
  /// Plain `dart:io` so the bytes arrive as they are sent; the server keeps
  /// its own history, so only the new question goes up. [sessionId] null
  /// starts a new chat (a [TitiSessionStarted] says its id).
  Stream<TitiEvent> ask(String message, {String? sessionId, List<String> images = const [], double? lat, double? lng}) async* {
    var session = _client.auth.currentSession;
    if (session == null) throw const AppException('Sign in again to chat with TiTi.');
    if (session.isExpired) {
      session = (await _client.auth.refreshSession()).session ?? session;
    }
    final http = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final req = await http.postUrl(Uri.parse('${Env.supabaseUrl}/functions/v1/titi'));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}')
        ..set('apikey', Env.supabasePublishableKey)
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'v': 2,
        'message': message,
        if (sessionId != null) 'session_id': sessionId else 'new_session': true,
        if (images.isNotEmpty) 'images': images,
        'lat': ?lat,
        'lng': ?lng,
      })));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = await res.transform(utf8.decoder).join();
        throw TitiHttpException(res.statusCode, body);
      }
      // A silent minute means the line dropped: give up rather than spin forever.
      final lines = res.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 60));
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final ev = TitiEvent.parse(line.substring(5).trim());
        if (ev == null) continue;
        yield ev;
        if (ev is TitiDone) return;
      }
    } finally {
      http.close(force: true);
    }
  }

  // ------------------------------------------------------------- chats ---

  /// My chats, latest first.
  Future<List<TitiSession>> sessions({int limit = 50}) async {
    final rows = await _client.from('titi_sessions').select('id, title, updated_at').order('updated_at', ascending: false).limit(limit);
    return rows.map(TitiSession.fromMap).toList();
  }

  /// One chat's newest [limit] messages, oldest first, with my photos signed
  /// for an hour.
  Future<List<TitiMessage>> history(String sessionId, {int limit = 80}) async {
    final rows = await _client
        .from('titi_messages')
        .select('id, role, content, parts, created_at')
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);
    final list = rows.reversed.toList();
    final paths = <String>{
      for (final r in list)
        if (r['role'] == 'user' && r['parts'] is Map && (r['parts'] as Map)['images'] is List)
          for (final p in ((r['parts'] as Map)['images'] as List)) if (p is String) p,
    };
    final urls = await _sign(paths.toList());
    return [
      for (final r in list)
        if (TitiMessage.fromRow(r, urls: urls) case final m when !m.isEmpty) m,
    ];
  }

  Future<Map<String, String>> _sign(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final signed = await _client.storage.from(_bucket).createSignedUrlsResult(paths, 3600);
      return {for (final s in signed) if (s case SignedUrlSuccess(:final path, :final signedUrl)) path: signedUrl};
    } catch (e) {
      if (kDebugMode) debugPrint('titi sign: $e');
      return const {};
    }
  }

  /// Deletes a chat: its photos first (nothing else can), then the chat and
  /// its messages. The daily limit and the cost log are kept server-side.
  Future<void> deleteSession(String id) async {
    final rows = await _client.from('titi_messages').select('parts').eq('session_id', id).eq('role', 'user').not('parts', 'is', null);
    final paths = [
      for (final r in rows)
        if (r['parts'] is Map && (r['parts'] as Map)['images'] is List)
          for (final p in ((r['parts'] as Map)['images'] as List)) if (p is String) p,
    ];
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(_bucket).remove(paths);
      } catch (e) {
        if (kDebugMode) debugPrint('titi remove photos: $e');
      }
    }
    await _client.from('titi_sessions').delete().eq('id', id);
  }

  // ------------------------------------------------------------ photos ---

  /// Uploads one photo to my folder and returns its path. [bytes] are
  /// already ~1280 px (the picker resizes them).
  Future<String> uploadPhoto({required String me, required Uint8List bytes}) async {
    final type = _imageType(bytes);
    if (type == null) throw const AppException('That photo type isn\'t supported. Try a JPEG or PNG.');
    final rand = math.Random().nextInt(1 << 32).toRadixString(36);
    final path = '$me/${DateTime.now().millisecondsSinceEpoch}_$rand.${type.$1}';
    await _client.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type.$2, cacheControl: kImmutableCacheControl));
    return path;
  }

  /// (extension, content type) from the first bytes; null for anything the
  /// bucket refuses (HEIC and friends).
  static (String, String)? _imageType(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return ('jpg', 'image/jpeg');
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return ('png', 'image/png');
    if (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return ('webp', 'image/webp');
    return null;
  }

  // ----------------------------------------------------------- actions ---

  /// Stamps an action card done or dismissed so it reloads that way. False
  /// when the answer isn't saved yet (it is, a moment after it streams).
  Future<bool> setActionStatus(String actionId, String status, {String? route}) async {
    final v = await _client.rpc('titi_action_status', params: {'p_action': actionId, 'p_status': status, 'p_route': ?route});
    return v == true;
  }
}

class TitiHttpException implements Exception {
  const TitiHttpException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'titi $status: $body';
}

/// Short and friendly, for the error row under an answer.
String titiErrorText(Object e) => switch (e) {
      AppException() => e.message,
      TitiHttpException(status: 401) => 'Sign in again to chat with TiTi.',
      // The titi function refuses without the member's OK for OpenAI.
      TitiHttpException(status: 403) => 'TiTi needs your OK to use OpenAI.',
      TitiHttpException(status: 503) => 'TiTi is off duty right now. Try again later.',
      TitiHttpException() => 'My radio cut out. Try again?',
      SocketException() || HttpException() || TimeoutException() || HandshakeException() => 'Can\'t reach TiTi. Check your connection and retry.',
      StorageException() => 'Couldn\'t send your photo. Try again?',
      _ => 'My radio cut out. Try again?',
    };

final titiRepositoryProvider = Provider<TitiRepository>((ref) => TitiRepository(ref.watch(supabaseProvider)));
