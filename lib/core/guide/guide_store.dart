import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/settings/application/settings_providers.dart';

/// Where guides read the Tips switch and the seen list, and save the list.
/// The app uses [SettingsGuideStore] (profiles.settings); tests override
/// [guideStoreProvider] with a [MemoryGuideStore].
abstract class GuideStore {
  /// The member's settings are known (profile loaded). Until then [tipsOn]
  /// and [seen] are only defaults, so nothing should show.
  bool get loaded;

  /// Done with onboarding (has a username). Guides never show before that.
  bool get onboarded;

  /// Settings → Page tips (profiles.settings.tips). Default on.
  bool get tipsOn;

  /// Guide ids already shown (profiles.settings.guides_seen).
  List<String> get seen;

  /// Saves the whole list (the server patch is a shallow merge).
  Future<void> saveSeen(List<String> ids);
}

/// profiles.settings, through [settingsProvider] and [SettingsActions.patch].
class SettingsGuideStore implements GuideStore {
  SettingsGuideStore(this._ref);
  final Ref _ref;

  @override
  bool get loaded => _ref.read(currentProfileProvider).hasValue;

  @override
  bool get onboarded => _ref.read(currentProfileProvider).value?.isOnboarded ?? false;

  @override
  bool get tipsOn => _ref.read(settingsProvider).tipsOn;

  @override
  List<String> get seen => _ref.read(settingsProvider).guidesSeen;

  @override
  Future<void> saveSeen(List<String> ids) => _ref.read(settingsActionsProvider).patch({'guides_seen': ids});
}

/// In memory: tests and previews.
class MemoryGuideStore implements GuideStore {
  MemoryGuideStore({this.loaded = true, this.onboarded = true, this.tipsOn = true, Iterable<String> seen = const []}) : seen = [...seen];

  @override
  bool loaded;

  @override
  bool onboarded;

  @override
  bool tipsOn;

  @override
  List<String> seen;

  /// Every list saved, oldest first.
  final saves = <List<String>>[];

  @override
  Future<void> saveSeen(List<String> ids) async {
    seen = [...ids];
    saves.add([...ids]);
  }
}

final guideStoreProvider = Provider<GuideStore>((ref) => SettingsGuideStore(ref));
