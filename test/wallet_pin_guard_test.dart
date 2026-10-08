import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/cards/application/cards_providers.dart';
import 'package:car_meet/features/cards/domain/cards.dart';
import 'package:car_meet/features/cards/presentation/new_trade_screen.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/safety/application/wallet_pin.dart';
import 'package:car_meet/features/titi/application/titi_actions.dart';
import 'package:car_meet/features/titi/domain/titi_message.dart';
import 'package:car_meet/features/vendors/application/vendors_providers.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the PIN sheet: records each ask and answers [unlock].
class _FakeGate extends WalletGate {
  _FakeGate(this.log, {this.unlock = true});
  final List<String> log;
  bool unlock;
  final forced = <bool>[];

  @override
  Future<bool> ensureUnlocked(BuildContext context, WidgetRef ref, {bool force = false}) async {
    log.add('gate');
    forced.add(force);
    return unlock;
  }

  @override
  void forget(WidgetRef ref) {}
}

/// Pumps a button that runs [body] with a real BuildContext and WidgetRef.
Future<void> _withRef(WidgetTester t, List<Override> overrides, Future<void> Function(BuildContext, WidgetRef) body) async {
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (ctx, ref, _) => TextButton(onPressed: () => body(ctx, ref), child: const Text('GO')),
        ),
      ),
    ),
  ));
  await t.tap(find.text('GO'));
  await t.pumpAndSettle();
}

const _card = CardType(id: 'c1', setId: 's1', number: 1, name: 'Myvi Kencang', rarity: CardRarity.common, color: Color(0xFF9AA0A8), active: true, sort: 1);

class _FakeCards extends CardsActions {
  _FakeCards(super.ref, this.log);
  final List<String> log;

  @override
  Future<String> proposeTrade({required String to, required List<String> offer, required List<String> request, String? message}) async {
    log.add('trade:$to:${offer.join(',')}');
    return 't1';
  }
}

class _FakeVendors extends VendorActions {
  _FakeVendors(super.ref, this.log);
  final List<String> log;

  @override
  Future<({String id, int pointsSpent})> claim(String voucherId) async {
    log.add('claim:$voucherId');
    return (id: 'claim-1', pointsSpent: 100);
  }
}

void main() {
  group('runWithWalletPin', () {
    testWidgets('asks for the PIN before the action; backing out skips it', (t) async {
      final log = <String>[];
      final gate = _FakeGate(log, unlock: false);
      bool? ran;
      await _withRef(t, [walletGateProvider.overrideWithValue(gate)], (ctx, ref) async {
        ran = await runWithWalletPin(ctx, ref, () async => log.add('action'));
      });
      expect(log, ['gate']);
      expect(ran, isFalse);
    });

    testWidgets('unlocked: the action runs after the gate', (t) async {
      final log = <String>[];
      bool? ran;
      await _withRef(t, [walletGateProvider.overrideWithValue(_FakeGate(log))], (ctx, ref) async {
        ran = await runWithWalletPin(ctx, ref, () async => log.add('action'));
      });
      expect(log, ['gate', 'action']);
      expect(ran, isTrue);
    });

    testWidgets('the server still says PIN_REQUIRED: ask again (forced) and retry once', (t) async {
      final log = <String>[];
      final gate = _FakeGate(log);
      var calls = 0;
      await _withRef(t, [walletGateProvider.overrideWithValue(gate)], (ctx, ref) async {
        await runWithWalletPin(ctx, ref, () async {
          calls++;
          log.add('action');
          if (calls == 1) throw const PostgrestException(message: 'PIN_SETUP_REQUIRED');
        });
      });
      expect(log, ['gate', 'action', 'gate', 'action']);
      expect(gate.forced, [false, true]);
    });

    testWidgets('a free voucher (askFirst false) goes straight to the server', (t) async {
      final log = <String>[];
      await _withRef(t, [walletGateProvider.overrideWithValue(_FakeGate(log))], (ctx, ref) async {
        await runWithWalletPin(ctx, ref, () async => log.add('action'), askFirst: false);
      });
      expect(log, ['action']);
    });

    testWidgets('other errors pass through untouched', (t) async {
      final log = <String>[];
      Object? caught;
      await _withRef(t, [walletGateProvider.overrideWithValue(_FakeGate(log))], (ctx, ref) async {
        try {
          await runWithWalletPin(ctx, ref, () async => throw const PostgrestException(message: 'This voucher has ended'));
        } catch (e) {
          caught = e;
        }
      });
      expect(log, ['gate']);
      expect((caught as PostgrestException).message, 'This voucher has ended');
    });
  });

  group('protected actions call ensureWalletUnlocked first', () {
    Future<List<String>> sendTrade(WidgetTester t, {required bool unlock}) async {
      final log = <String>[];
      t.view.physicalSize = const Size(393, 851) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final friend = Profile(id: 'f1', username: 'sean', displayName: 'Sean', createdAt: DateTime(2026));
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const NewTradeScreen(withUserId: 'f1'))]);
      await t.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          walletGateProvider.overrideWithValue(_FakeGate(log, unlock: unlock)),
          cardsActionsProvider.overrideWith((ref) => _FakeCards(ref, log)),
          friendsProvider.overrideWith((ref) async => [friend]),
          cardTypesProvider.overrideWith((ref) async => const [_card]),
          myCardsProvider.overrideWith((ref) async => [UserCard(id: 'uc1', cardId: 'c1', status: 'held', source: 'box', acquiredAt: DateTime(2026))]),
          friendCardsProvider('f1').overrideWith((ref) async => const []),
          cardSettingsProvider.overrideWith((ref) async => const CardSettings()),
        ],
        child: MaterialApp.router(theme: AppTheme.current, routerConfig: router),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(AppIcons.plus).first);
      await t.pump();
      await t.tap(find.textContaining('Send offer'));
      await t.pumpAndSettle();
      return log;
    }

    testWidgets('trade offer: locked wallet sends nothing', (t) async {
      expect(await sendTrade(t, unlock: false), ['gate']);
    });

    testWidgets('trade offer: unlocked, the offer goes out after the gate', (t) async {
      expect(await sendTrade(t, unlock: true), ['gate', 'trade:f1:uc1']);
    });

    testWidgets('TiTi voucher claim: a points voucher asks for the PIN first', (t) async {
      final log = <String>[];
      final voucher = Voucher(
        id: 'v1',
        vendorId: 'vd1',
        title: 'RM10 off',
        kind: DiscountKind.amount,
        value: 10,
        minSpend: 0,
        pointsCost: 100,
        claimsCount: 0,
        perUserLimit: 1,
        startsAt: DateTime(2026),
        active: true,
      );
      Object? caught;
      await _withRef(t, [
        walletGateProvider.overrideWithValue(_FakeGate(log, unlock: false)),
        vendorActionsProvider.overrideWith((ref) => _FakeVendors(ref, log)),
        shopVouchersProvider.overrideWith((ref) async => [voucher]),
      ], (ctx, ref) async {
        await ref.read(shopVouchersProvider.future);
        try {
          await runTitiAction(ctx, ref, const TitiAction(kind: 'claim_voucher', id: 'a1', label: 'Claim · 100 pts', title: 'RM10 off', target: 'v1'));
        } catch (e) {
          caught = e;
        }
      });
      expect(log, ['gate'], reason: 'no claim without the PIN');
      expect(caught.toString(), 'Needs your wallet PIN.');
    });
  });
}
