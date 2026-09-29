import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ticks each time the Home tab is tapped while already on Home. The feed
/// listens: back to the Feed tab, scroll to the top, fresh posts.
class HomeReselectNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

final homeReselectProvider = NotifierProvider<HomeReselectNotifier, int>(HomeReselectNotifier.new);
