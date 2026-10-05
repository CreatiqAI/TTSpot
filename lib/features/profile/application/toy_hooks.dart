import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the backend for a (new) toy car render of one car: `cars.toy_status`
/// goes to 'pending' and the garage shows the "Building your toy car…"
/// fallback until `toy_url` lands.
typedef ToyRequester = Future<void> Function(String carId);

/// The hook the garage calls from "Remake toy car" in the car's actions. Null
/// until the toy backend is wired in (the entry is hidden then); the toy
/// repository overrides it with its own `requestToy`.
final toyRequesterProvider = Provider<ToyRequester?>((ref) => null);

/// Something the owner's garage keeps watched while it is open, so toys land
/// without a pull to refresh: the toy backend's `toyWatcherProvider` (it
/// invalidates the cars when `toy_status` changes). Null until wired.
final toyWatchProvider = Provider<Provider<void>?>((ref) => null);
