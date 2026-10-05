import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'toy_providers.dart';

/// Asks the backend for a (new) toy car render of one car: `cars.toy_status`
/// goes to 'pending' and the garage shows the "Building your toy car…"
/// fallback until `toy_url` lands.
typedef ToyRequester = Future<void> Function(String carId);

/// The hook the garage calls from "Remake toy car" in the car's actions.
/// Null hides the entry (tests override it that way).
final toyRequesterProvider = Provider<ToyRequester?>((ref) => (carId) => ref.read(toyActionsProvider).remake(carId));
