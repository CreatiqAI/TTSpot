import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';

/// My settings (profiles.settings). Missing keys fall back to defaults here.
class AppSettings {
  const AppSettings(this._m);
  final Map<String, dynamic> _m;

  bool _b(String k, bool d) => (_m[k] as bool?) ?? d;

  bool get notifMeets => _b('notif_meets', true);
  bool get notifMessages => _b('notif_messages', true);
  bool get notifFriends => _b('notif_friends', true);
  bool get notifTt => _b('notif_tt', true);
  bool get notifRewards => _b('notif_rewards', true);

  /// 'auto' (light by day, dark after 7 pm) | 'light' | 'dark'
  String get mapTheme => (_m['map_theme'] as String?) ?? 'auto';

  /// Who can start a chat with me: 'everyone' | 'friends'
  String get dmFrom => (_m['dm_from'] as String?) ?? 'everyone';

  /// Show my car colour to friends on the map (else the default silver).
  bool get showCarColor => _b('show_car_color', true);

  /// Auto check-in when I'm at a meet I joined.
  bool get autoCheckin => _b('auto_checkin', true);

  /// Units: 'km' | 'mi'
  String get units => (_m['units'] as String?) ?? 'km';
}

/// Profile settings plus anything saved this session, so a toggle flips at
/// once instead of waiting for the profile to refetch.
class SettingsNotifier extends Notifier<AppSettings> {
  final _local = <String, dynamic>{};

  @override
  AppSettings build() {
    final p = ref.watch(currentProfileProvider).value;
    return AppSettings({...?p?.settings, ..._local});
  }

  void apply(Map<String, dynamic> patch) {
    _local.addAll(patch);
    state = AppSettings({...state._m, ...patch});
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsActions {
  SettingsActions(this._ref);
  final Ref _ref;

  Future<void> patch(Map<String, dynamic> patch) async {
    _ref.read(settingsProvider.notifier).apply(patch);
    await _ref.read(supabaseProvider).rpc('update_my_settings', params: {'p_patch': patch});
    _ref.invalidate(currentProfileProvider);
  }

  Future<void> deleteAccount() async {
    await _ref.read(supabaseProvider).rpc('delete_my_account');
    await _ref.read(supabaseProvider).auth.signOut();
  }
}

final settingsActionsProvider = Provider<SettingsActions>((ref) => SettingsActions(ref));
