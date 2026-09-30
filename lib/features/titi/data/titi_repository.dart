import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      'delta' => TitiDelta(j['text'] as String? ?? ''),
      'break' => const TitiBreak(),
      'card' => switch (TitiCard.fromMap(j)) { final TitiCard c => TitiCardEvent(c), null => null },
      'chips' => TitiChips([for (final o in (j['options'] as List? ?? const [])) if (o is String && o.trim().isNotEmpty) o.trim()]),
      'status' => TitiStatus(j['text'] as String? ?? '', j['tool'] as String?),
      'error' => TitiError(j['text'] as String? ?? 'My radio cut out. Try again?'),
      'done' => const TitiDone(),
      _ => null,
    };
  }
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

class TitiDone extends TitiEvent {
  const TitiDone();
}

/// The chat with TiTi: the answer stream from the `titi` function and the
/// saved history in `titi_messages` (RLS: my own rows only).
class TitiRepository {
  TitiRepository(this._client);
  final SupabaseClient _client;

  /// Streams one answer, token by token. Cancelling the subscription closes
  /// the connection, which stops the model on the server too.
  ///
  /// Plain `dart:io` so the bytes arrive as they are sent; the server keeps
  /// its own history, so only the new question goes up.
  Stream<TitiEvent> ask(String message, {double? lat, double? lng}) async* {
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
      req.add(utf8.encode(jsonEncode({'message': message, 'lat': ?lat, 'lng': ?lng})));
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

  /// My chat, newest [limit] rows, oldest first. An answer remembers the
  /// question before it, for Retry.
  Future<List<TitiMessage>> history({int limit = 60}) async {
    final rows = await _client.from('titi_messages').select('id, role, content, parts, created_at').order('created_at', ascending: false).limit(limit);
    final list = rows.reversed.toList();
    final out = <TitiMessage>[];
    String? lastQuestion;
    for (final r in list) {
      if (r['role'] == 'user') lastQuestion = r['content'] as String?;
      final m = TitiMessage.fromRow(r, question: r['role'] == 'user' ? null : lastQuestion);
      if (!m.isEmpty) out.add(m);
    }
    return out;
  }

  /// Deletes my whole chat. The daily limit and the cost log are kept server-side.
  Future<void> clear() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client.from('titi_messages').delete().eq('user_id', me);
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
      TitiHttpException(status: 503) => 'TiTi is off duty right now. Try again later.',
      TitiHttpException() => 'My radio cut out. Try again?',
      SocketException() || HttpException() || TimeoutException() || HandshakeException() => 'Can\'t reach TiTi. Check your connection and retry.',
      _ => 'My radio cut out. Try again?',
    };

final titiRepositoryProvider = Provider<TitiRepository>((ref) => TitiRepository(ref.watch(supabaseProvider)));
