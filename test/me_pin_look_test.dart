import 'package:car_meet/features/map/presentation/widgets/car_marker.dart';
import 'package:flutter_test/flutter_test.dart';

/// My pin up close never flashes the old stand-in (photo badge / drawn car)
/// before my toy: the dot holds the place until my cars and my toy's image
/// are on the phone. Only a car with no toy shows the stand-in.
void main() {
  const toy = 'https://x.supabase.co/storage/v1/object/public/cars/toy.png';

  test('cars not loaded yet: the dot, whatever the toy', () {
    expect(mePinLook(carsLoaded: false), MePinLook.dot);
    expect(mePinLook(carsLoaded: false, toyUrl: toy, toyReady: true), MePinLook.dot);
  });

  test('a toy still loading or failed: the dot; loaded: the toy', () {
    expect(mePinLook(carsLoaded: true, toyUrl: toy), MePinLook.dot);
    expect(mePinLook(carsLoaded: true, toyUrl: toy, toyReady: false), MePinLook.dot);
    expect(mePinLook(carsLoaded: true, toyUrl: toy, toyReady: true), MePinLook.toy);
  });

  test('no toy at all (or no car): the stand-in, once my cars are in', () {
    expect(mePinLook(carsLoaded: true), MePinLook.standIn);
  });
}
