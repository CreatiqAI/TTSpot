import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/directions/directions.dart';
import '../../events/application/event_providers.dart';
import '../../map/presentation/widgets/place_card.dart' show ttHere;
import '../../safety/application/wallet_pin.dart';
import '../../social/application/community_providers.dart';
import '../../vendors/application/vendors_providers.dart';
import '../domain/titi_message.dart';
import '../presentation/titi_routes.dart';

/// Does what an action card says, when the member taps it, with the same code
/// the rest of the app runs for that button (RSVP, save, directions, TT here,
/// claim). TiTi's function never writes for the member; this is the only
/// place an action happens. Returns where the card leads afterwards (a
/// claimed voucher's QR), if anywhere. Throws a friendly error on failure.
Future<String?> runTitiAction(BuildContext context, WidgetRef ref, TitiAction a) async {
  String target() {
    final id = a.target;
    if (id == null || id.isEmpty) throw const AppException('That one is missing its details. Ask TiTi again.');
    return id;
  }

  switch (a.kind) {
    case 'join_meet':
      await ref.read(eventActionsProvider).join(target());
    case 'leave_meet':
      await ref.read(eventActionsProvider).leave(target());
    case 'save_spot':
      final actions = ref.read(communityActionsProvider);
      // A toggle: if it was saved already (from another screen), save it back.
      if (!await actions.toggleSavePlace(target())) await actions.toggleSavePlace(target());
    case 'directions':
      final lat = a.lat, lng = a.lng;
      if (lat == null || lng == null) throw const AppException('No location for that one.');
      await openDirections(context, lat: lat, lng: lng, label: a.title.isEmpty ? null : a.title);
    case 'tt_here':
      final place = await ref.read(placeProvider(target()).future);
      if (place == null) throw const AppException('That spot is gone.');
      if (context.mounted) await ttHere(context, ref, place, a.title.isEmpty ? place.name : a.title);
    case 'open_page' || 'open_box':
      final route = a.route;
      if (route == null || !openTitiRoute(context, route)) throw const AppException('That page can\'t be opened.');
    case 'claim_voucher':
      // Points vouchers need the wallet PIN. When the shop list doesn't know
      // the price, the server asks (PIN_REQUIRED) and the sheet shows then.
      final id = target();
      final cost = ref.read(shopVouchersProvider).value?.where((v) => v.id == id).firstOrNull?.pointsCost;
      String? claimId;
      final done = await runWithWalletPin(context, ref, () async => claimId = (await ref.read(vendorActionsProvider).claim(id)).id, askFirst: cost != null && cost > 0);
      if (!done || claimId == null) throw const AppException('Needs your wallet PIN.');
      return Routes.voucherQr(claimId!);
    default:
      throw const AppException('Update TT Spot to do that one.');
  }
  return null;
}
