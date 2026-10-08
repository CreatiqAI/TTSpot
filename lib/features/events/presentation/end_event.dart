import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../application/event_providers.dart';
import '../domain/event.dart';

/// What a host can do to close an event: end it while it runs, cancel it
/// before it starts.
enum EventCloseAction { end, cancel }

/// The close action [e] offers its hosts at [now]: [EventCloseAction.end]
/// from the start until it closes, [EventCloseAction.cancel] before the
/// start, null when it's cancelled or already over.
EventCloseAction? eventCloseAction(Event e, DateTime now) {
  if (e.isCancelled || !now.isBefore(e.closesAt)) return null;
  return now.isBefore(e.startsAt) ? EventCloseAction.cancel : EventCloseAction.end;
}

/// The row label: "End event now" / "Cancel event" ([noun]: event or meet).
String eventCloseLabel(EventCloseAction a, {String noun = 'event'}) => switch (a) {
      EventCloseAction.end => 'End $noun now',
      EventCloseAction.cancel => 'Cancel $noun',
    };

/// The icon next to [eventCloseLabel].
IconData eventCloseIcon(EventCloseAction a) => switch (a) {
      EventCloseAction.end => AppIcons.flagCheckered,
      EventCloseAction.cancel => AppIcons.xCircle,
    };

/// Asks first, then ends or cancels [e] (host circle only; the server
/// checks). Works from any context under the app's ProviderScope.
Future<void> closeEventFlow(BuildContext context, Event e, {String noun = 'event'}) async {
  final action = eventCloseAction(e, DateTime.now());
  if (action == null) return;
  final end = action == EventCloseAction.end;
  final ok = await confirmSheet(
    context,
    icon: eventCloseIcon(action),
    title: end ? 'End this $noun now?' : 'Cancel this $noun?',
    body: end ? 'It closes for everyone and check-ins stop.' : "Everyone who joined gets told. This can't be undone.",
    confirm: end ? 'End now' : 'Cancel $noun',
    cancel: end ? 'Not yet' : 'Keep it',
  );
  if (!ok || !context.mounted) return;
  final actions = ProviderScope.containerOf(context, listen: false).read(eventActionsProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (end) {
      await actions.endNow(e.id);
    } else {
      await actions.cancel(e.id);
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${noun[0].toUpperCase()}${noun.substring(1)} ${end ? 'ended' : 'cancelled'}.')));
  } catch (err) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(friendlyError(err))));
  }
}
