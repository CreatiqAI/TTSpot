import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the backend for a (new) toy car render of one car: `cars.toy_status`
/// goes to 'pending' and the garage shows the "Building your toy car…"
/// fallback until `toy_url` lands.
typedef ToyRequester = Future<void> Function(String carId);

/// The hook the garage calls from "Remake toy car" in the car's actions. Null
/// until the toy backend is wired in (the entry is hidden then); the toy
/// repository overrides it with its own `requestToy`.
final toyRequesterProvider = Provider<ToyRequester?>((ref) => null);
