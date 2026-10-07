import 'package:car_meet/core/places/place_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('placeLabel', () {
    test("owner's example: the address already starts with the name", () {
      const addr = '2, Jln Suria Park 1, Bandar Damai Perdana, 56000 Kuala Lumpur, Wilayah Persekutuan Kuala Lumpur, Malaysia';
      expect(placeLabel('2, Jalan Suria Park 1', addr), addr);
      expect(placeLabel('2, Jln Suria Park 1', addr), addr);
    });

    test('shop name not in the address: name, address', () {
      expect(
        placeLabel('12V Auto Accessories', '23, Jalan PJS 11/7, Bandar Sunway, 47500 Petaling Jaya, Selangor, Malaysia'),
        '12V Auto Accessories, 23, Jalan PJS 11/7, Bandar Sunway, 47500 Petaling Jaya, Selangor, Malaysia',
      );
    });

    test('case, punctuation, spacing and abbreviations do not matter', () {
      expect(placeLabel('Sunway  Pyramid', 'SUNWAY PYRAMID, 3, Jalan PJS 11/15, Bandar Sunway'), 'SUNWAY PYRAMID, 3, Jalan PJS 11/15, Bandar Sunway');
      expect(placeLabel('Lorong Kenari 3', 'Lrg. Kenari 3, Taman Bukit'), 'Lrg. Kenari 3, Taman Bukit');
      expect(placeLabel('Taman Melawati', 'Jln Bandar Melawati, Tmn Melawati, 53100 KL'), 'Jln Bandar Melawati, Tmn Melawati, 53100 KL');
    });

    test('whole words only: a near-identical house number still gets the name', () {
      expect(placeLabel('2, Jalan Suria Park 1', '12, Jalan Suria Park 10, Bandar Damai Perdana'),
          '2, Jalan Suria Park 1, 12, Jalan Suria Park 10, Bandar Damai Perdana');
    });

    test('address-only and name-only results', () {
      expect(placeLabel('', '5, Jalan Ampang, Kuala Lumpur'), '5, Jalan Ampang, Kuala Lumpur');
      expect(placeLabel('Mamak Sri Melur', ''), 'Mamak Sri Melur');
      expect(placeLabel('  ', '  '), '');
    });
  });
}
