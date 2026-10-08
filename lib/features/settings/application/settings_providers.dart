import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../events/application/live_activity.dart';
import '../../profile/data/profile_repository.dart';

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
  bool get notifFriendPosts => _b('notif_friend_posts', true);
  bool get notifFriendTt => _b('notif_friend_tt', true);
  bool get notifClubMembers => _b('notif_club_members', true);
  bool get notifFollowers => _b('notif_followers', true);
  bool get notifMentions => _b('notif_mentions', true);
  bool get notifReplies => _b('notif_replies', true);
  bool get notifClubFollows => _b('notif_club_follows', true);

  /// "TiTi tips": TiTi may message me first, up to three a day (titi-nudge).
  bool get titiTips => _b('titi_tips', true);

  /// "Page tips": TiTi's first-visit guides (lib/core/guide). Default on.
  bool get tipsOn => _b('tips', true);

  /// Guide ids already shown, on any phone (GuideIds).
  List<String> get guidesSeen => (_m['guides_seen'] as List?)?.whereType<String>().toList() ?? const [];

  /// 'auto' (light by day, dark after 7 pm) | 'light' | 'dark'
  /// 'auto' (light 7 am–7 pm, dark otherwise) | 'light' | 'dark'. Older builds saved it as map_theme.
  String get theme => (_m['theme'] as String?) ?? (_m['map_theme'] as String?) ?? 'auto';
  String get mapTheme => theme;

  /// Background behind every chat's messages: 'titi' (default) | 'ttspot' | 'night'.
  /// Only an explicit pick is stored; members who never chose get the default.
  String get chatWallpaper => switch (_m['chat_wallpaper']) { 'night' => 'night', 'ttspot' => 'ttspot', _ => 'titi' };

  /// Who can start a chat with me: 'everyone' | 'friends'
  String get dmFrom => (_m['dm_from'] as String?) ?? 'everyone';
  /// Who can fetch my phone number to call me: 'nobody' | 'friends'
  String get callsFrom => (_m['calls_from'] as String?) ?? 'nobody';
  bool get introSeen => _b('intro_seen', false);
  /// The map key has been open once; from then on it starts folded.
  bool get mapKeySeen => _b('map_key_seen', false);

  /// Directions / Go now open this app: 'ask' (the chooser, default) |
  /// 'waze' | 'google' | 'apple' (iPhone). See core/directions/directions.dart.
  String get directionsApp => (_m['directions_app'] as String?) ?? 'ask';

  /// Show my car colour to friends on the map (else the default silver).
  bool get showCarColor => _b('show_car_color', true);

  /// Auto check-in when I'm at a meet I joined.
  bool get autoCheckin => _b('auto_checkin', true);

  /// iPhone: the meet countdown on the lock screen / Dynamic Island.
  bool get liveActivities => _b('live_activities', true);

  /// Meets whose Live Activity was already shown (newest last, at most 30).
  /// They never start again by themselves, so a swipe-away sticks.
  List<String> get liveActivitiesShown => (_m['la_started'] as List?)?.whereType<String>().toList() ?? const [];

  /// "Hide my number plate" when adding car photos (off: the original goes up).
  bool get hidePlate => _b('hide_plate', false);

  /// Units: 'km' | 'mi'
  String get units => (_m['units'] as String?) ?? 'km';

  /// My garage's look: 'bay' (roller-door bay, the default) | 'cards'.
  String get garageView => (_m['garage_view'] as String?) ?? 'bay';

  /// My OKs to send data to a third-party AI (Apple 5.1.2(i)), as
  /// `ai_consent: {"titi": iso, "toy": iso, "safety": iso}`: the date each
  /// was given. Only non-empty strings count; anything else reads as no.
  Map<String, String> get aiConsent {
    final raw = _m['ai_consent'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is String && (e.value as String).isNotEmpty) e.key as String: e.value as String,
    };
  }

  /// TiTi may send my messages, photos and app context to OpenAI.
  bool get titiConsent => aiConsent.containsKey('titi');

  /// My car photos may go to Kie.ai for the toy car.
  bool get toyConsent => aiConsent.containsKey('toy');

  /// I've seen that posts and moments are checked by OpenAI's safety filter.
  bool get safetyConsent => aiConsent.containsKey('safety');

  /// When [key] ('titi' | 'toy' | 'safety') was agreed to, or null.
  DateTime? aiConsentAt(String key) {
    final v = aiConsent[key];
    return v == null ? null : DateTime.tryParse(v);
  }
}

/// The whole `ai_consent` object to save: [current] plus [key] agreed [at]
/// (UTC ISO). An earlier date for [key] is kept, so the first OK stands.
Map<String, String> withAiConsent(Map<String, String> current, String key, DateTime at) =>
    {...current, key: current[key] ?? at.toUtc().toIso8601String()};

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

  /// Records my OK for [key] ('titi' | 'safety') with today's date. The
  /// settings merge is shallow, so the whole `ai_consent` object goes up.
  /// (Toy cars go through `allow_toy_cars`, which also books the toys.)
  Future<void> recordAiConsent(String key) =>
      patch({'ai_consent': withAiConsent(_ref.read(settingsProvider).aiConsent, key, DateTime.now())});

  /// Marks [key] as agreed on this phone right away (after a server call such
  /// as `allow_toy_cars` already stored it).
  void applyAiConsent(String key) =>
      _ref.read(settingsProvider.notifier).apply({'ai_consent': withAiConsent(_ref.read(settingsProvider).aiConsent, key, DateTime.now())});

  Future<void> deleteAccount() async {
    // The private originals of blurred car photos first: storage files don't
    // go with the account rows, and only the signed-in owner can remove them.
    final me = _ref.read(currentUserIdProvider);
    if (me != null) {
      try {
        await _ref.read(profileRepositoryProvider).deleteAllCarOriginals(me);
      } catch (_) {
        // The account still goes; these stay private (owner-only RLS).
      }
    }
    await _ref.read(supabaseProvider).rpc('delete_my_account');
    await _ref.read(liveActivityServiceProvider).endAll();
    await _ref.read(supabaseProvider).auth.signOut();
  }
}

final settingsActionsProvider = Provider<SettingsActions>((ref) => SettingsActions(ref));
