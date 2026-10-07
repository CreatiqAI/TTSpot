import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/expo/exhibitors/domain/exhibitor.dart';
import 'package:car_meet/features/expo/exhibitors/domain/exhibitor_import.dart';
import 'package:car_meet/features/expo/exhibitors/presentation/exhibitors_screen.dart';
import 'package:car_meet/features/floorplan/domain/floorplan.dart';
import 'package:car_meet/features/floorplan/presentation/floorplan_canvas.dart';
import 'package:car_meet/features/floorplan/presentation/floorplan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Exhibitor _ex(String id, String name, {List<String> booths = const [], String? category, String? partner, String? logo, int sort = 0}) => Exhibitor(
      id: id,
      eventId: 'ev',
      name: name,
      booths: booths,
      category: category,
      partnerVendorId: partner,
      partnerLogo: logo,
      sort: sort,
    );

FloorPin _pin(String id, String label, {double x = 0.5, double y = 0.5, double? w, double? h, String? ex, String? partner, PinKind kind = PinKind.booth, String level = 'L1'}) =>
    FloorPin(id: id, levelId: level, kind: kind, label: label, x: x, y: y, w: w, h: h, exhibitorId: ex, partnerVendorId: partner);

void main() {
  group('parseBoothCodes', () {
    test('splits, trims, upper-cases and drops repeats', () {
      expect(parseBoothCodes('A019, a024 / B7 & B8;B9|C1  C2'), ['A019', 'A024', 'B7', 'B8', 'B9', 'C1', 'C2']);
      expect(parseBoothCodes('A019,A019, a019'), ['A019']);
      expect(parseBoothCodes('  '), isEmpty);
    });

    test('caps code length and count', () {
      expect(parseBoothCodes('X' * 30).single.length, 20);
      expect(parseBoothCodes(List.generate(60, (i) => 'B$i').join(',')).length, 40);
    });
  });

  group('parseExhibitorList', () {
    test('CSV with quoted fields, commas inside quotes and doubled quotes', () {
      const csv = 'Company,Booth No.,Category,Country,Phone,E-mail,Web Site,Description\n'
          '"Acme Wheels, Sdn Bhd","A019, A024",Wheels,Malaysia,+60 3-1234 5678,hi@acme.my,acme.my,"The ""best"" rims, forged"\n'
          'Bolt Co,B001,Car care,Japan,,,,\n';
      final r = parseExhibitorList(csv);
      expect(r.error, isNull);
      expect(r.rows, hasLength(2));
      final a = r.rows.first;
      expect(a.name, 'Acme Wheels, Sdn Bhd');
      expect(a.booths, ['A019', 'A024']);
      expect(a.category, 'Wheels');
      expect(a.country, 'Malaysia');
      expect(a.phone, '+60 3-1234 5678');
      expect(a.email, 'hi@acme.my');
      expect(a.website, 'acme.my');
      expect(a.about, 'The "best" rims, forged');
      expect(r.rows[1].phone, isNull);
      expect(r.rows[1].toJson().containsKey('phone'), isFalse);
      expect(r.rows[1].toJson()['booths'], ['B001']);
    });

    test('tab-separated paste from a spreadsheet', () {
      const tsv = 'Exhibitor\tBooth\tCategory\r\n'
          'Acme Wheels\tA019 A024\tWheels, rims\r\n'
          '\t\t\r\n'
          'Grip Tyres\tC101/C102\tTyres\r\n';
      final r = parseExhibitorList(tsv);
      expect(r.ok, isTrue);
      expect(r.rows.map((e) => e.name), ['Acme Wheels', 'Grip Tyres']);
      expect(r.rows.first.booths, ['A019', 'A024']);
      expect(r.rows.first.category, 'Wheels, rims');
      expect(r.rows.last.booths, ['C101', 'C102']);
    });

    test('semicolon CSV, line breaks inside quotes, spaces before a quote', () {
      const csv = 'Name;Booths;About\nAcme; "A1; A2";"Line one\nline two"\n';
      final r = parseExhibitorList(csv);
      expect(r.rows.single.booths, ['A1', 'A2']);
      expect(r.rows.single.about, 'Line one\nline two');
    });

    test('same name merges booths and fills blanks', () {
      const csv = 'name,booth,category,phone\nAcme,A1,,\nACME,A2,Wheels,123456\nacme,A1,Other,\n';
      final r = parseExhibitorList(csv);
      expect(r.rows, hasLength(1));
      expect(r.rows.single.name, 'Acme');
      expect(r.rows.single.booths, ['A1', 'A2']);
      expect(r.rows.single.category, 'Wheels');
      expect(r.rows.single.phone, '123456');
    });

    test('rows without a name are skipped and counted', () {
      final r = parseExhibitorList('Name,Booth\n,A1\nAcme,A2\n');
      expect(r.rows, hasLength(1));
      expect(r.skipped, 1);
    });

    test('needs a name column', () {
      final r = parseExhibitorList('Booth,Category\nA1,Wheels\n');
      expect(r.ok, isFalse);
      expect(r.error, contains('Name'));
      expect(parseExhibitorList('   ').error, isNotNull);
    });

    test('loose header matching', () {
      expect(fieldForHeader('Company Name'), ImportField.name);
      expect(fieldForHeader('Contact Person'), isNull);
      expect(fieldForHeader('Contact Name'), isNull);
      expect(fieldForHeader('Booth No.'), ImportField.booths);
      expect(fieldForHeader('Stand'), ImportField.booths);
      expect(fieldForHeader('Tel'), ImportField.phone);
      expect(fieldForHeader('Email Address'), ImportField.email);
      expect(fieldForHeader('URL'), ImportField.website);
      expect(fieldForHeader('Product Category'), ImportField.category);
      expect(fieldForHeader('Country of origin'), ImportField.country);
      expect(fieldForHeader('About us'), ImportField.about);
      expect(fieldForHeader('Notes'), isNull);
      // First matching column wins.
      expect(matchHeaders(['Name', 'Brand', 'Booth'])[ImportField.name], 0);
    });

    test('delimiter detection', () {
      expect(detectDelimiter('a\tb,c\n'), '\t');
      expect(detectDelimiter('a;b\n'), ';');
      expect(detectDelimiter('a,b;c\n'), ',');
    });
  });

  group('Exhibitor', () {
    test('fromMap reads the RPC row', () {
      final e = Exhibitor.fromMap({
        'id': 'x1',
        'event_id': 'ev',
        'name': 'Acme Wheels',
        'booths': ['A019', 'A024'],
        'category': ' ',
        'partner_vendor_id': 'v1',
        'partner_logo': 'https://x/logo.png',
        'partner_name': 'Acme Shop',
        'pin_count': 2,
      });
      expect(e.category, isNull);
      expect(e.isPartner, isTrue);
      expect(e.displayLogo, 'https://x/logo.png');
      expect(e.boothsLabel, 'A019, A024');
      expect(e.pinCount, 2);
      expect(e.initials, 'AW');
    });

    test('search matches name, booth code, category and country', () {
      final e = Exhibitor(id: '1', eventId: 'ev', name: 'Acme Wheels', booths: const ['A019'], category: 'Rims', country: 'Malaysia');
      expect(e.matches('a019'), isTrue);
      expect(e.matches('rims malaysia'), isTrue);
      expect(e.matches('acme japan'), isFalse);
      expect(e.matches(''), isTrue);
    });

    test('partners first, then sort, then name', () {
      final out = sortExhibitors([_ex('1', 'zeta'), _ex('2', 'Alpha'), _ex('3', 'Mid', partner: 'v'), _ex('4', 'Beta', sort: -1)]);
      expect(out.map((e) => e.id), ['3', '4', '2', '1']);
    });

    test('categories by count then name', () {
      final cats = exhibitorCategories([_ex('1', 'a', category: 'Tyres'), _ex('2', 'b', category: 'Wheels'), _ex('3', 'c', category: 'Wheels'), _ex('4', 'd', category: 'Audio')]);
      expect(cats, ['Wheels', 'Audio', 'Tyres']);
    });

    test('contact links', () {
      expect(websiteUri('acme.my').toString(), 'https://acme.my');
      expect(websiteUri('http://acme.my/x').toString(), 'http://acme.my/x');
      expect(websiteUri(''), isNull);
      expect(phoneUri('+60 3-1234 5678').toString(), 'tel:+60312345678');
      expect(phoneUri('12'), isNull);
      expect(emailUri('hi@acme.my').toString(), 'mailto:hi@acme.my');
      expect(emailUri('nope'), isNull);
      expect(initialsOf('& co'), 'C');
      expect(initialsOf(''), '?');
    });
  });

  group('booth pins', () {
    test('FloorPin reads w/h and exhibitor; boxes only for sized booths', () {
      final p = FloorPin.fromMap({'id': 'p', 'level_id': 'L', 'kind': 'booth', 'label': ' a019 ', 'x': 0.5, 'y': 0.5, 'w': 0.1, 'h': 0.2, 'exhibitor_id': 'x1'});
      expect(p.isBox, isTrue);
      expect(p.exhibitorId, 'x1');
      expect(p.code, 'A019');
      expect(p.rect, const Rect.fromLTRB(0.45, 0.4, 0.55, 0.6));
      expect(_pin('s', 'S', kind: PinKind.stage, w: 0.1, h: 0.1).isBox, isFalse);
      expect(_pin('b', 'B').isBox, isFalse);
      expect(p.copyWith(clearSize: true).isBox, isFalse);
      expect(p.copyWith(clearExhibitor: true).exhibitorId, isNull);
    });

    test('boothPinsFor finds linked pins and pins by code', () {
      final levels = [
        FloorLevel(id: 'L1', eventId: 'ev', name: 'Hall A', sort: 0, pins: [_pin('1', 'A019', ex: 'x1'), _pin('2', 'a024'), _pin('3', 'B001'), _pin('4', 'A024', kind: PinKind.stage)]),
        FloorLevel(id: 'L2', eventId: 'ev', name: 'Hall B', sort: 1, pins: [_pin('5', 'C1', ex: 'x1', level: 'L2')]),
      ];
      final pins = boothPinsFor(levels, exhibitorId: 'x1', boothCodes: const ['A024 ']);
      expect(pins.map((p) => p.id), ['1', '2', '5']);
    });

    test('BoothSize presets come out square for the image aspect', () {
      final (w, h) = BoothSize.medium.fractions(2);
      expect(w, BoothSize.medium.width);
      expect(h, closeTo(w * 2, 1e-9));
      expect(BoothSize.nearest(0.03), BoothSize.medium);
      expect(BoothSize.nearest(null), isNull);
    });

    test('boundsOf', () {
      expect(boundsOf(const []), isNull);
      expect(boundsOf(const [Rect.fromLTWH(0.1, 0.1, 0.1, 0.1), Rect.fromLTWH(0.5, 0.6, 0, 0)]), const Rect.fromLTRB(0.1, 0.1, 0.5, 0.6));
    });

    test('partner logos: exhibitor partner first, then the pin partner', () {
      final level = FloorLevel(id: 'L1', eventId: 'ev', name: 'A', sort: 0, pins: [
        _pin('1', 'A1', ex: 'x1'),
        _pin('2', 'A2', ex: 'x2'),
        _pin('3', 'A3', partner: 'v9'),
        _pin('4', 'S', kind: PinKind.stage, partner: 'v9'),
      ]);
      final logos = partnerLogosFor(level, {'x1': _ex('x1', 'P', partner: 'v1', logo: 'L1'), 'x2': _ex('x2', 'Plain')}, {'v9': 'L9'});
      expect(logos, {'1': 'L1', '3': 'L9'});
    });

    test('focusMatrix centres the booth in the padded viewport', () {
      const pad = EdgeInsets.fromLTRB(12, 12, 72, 12);
      const viewport = Size(400, 600);
      const origin = Offset(12, 100);
      const plan = Size(316, 316);
      final m = focusMatrix(rect: const Rect.fromLTWH(0.2, 0.3, 0.02, 0.02), viewport: viewport, padding: pad, planOrigin: origin, planSize: plan);
      final s = m.getMaxScaleOnAxis();
      expect(s, greaterThan(1));
      final centre = Offset(origin.dx + 0.21 * plan.width, origin.dy + 0.31 * plan.height);
      final screen = MatrixUtils.transformPoint(m, centre);
      expect(screen.dx, closeTo(12 + (400 - 84) / 2, 0.01));
      expect(screen.dy, closeTo(12 + (600 - 24) / 2, 0.01));
    });
  });

  group('widgets', () {
    Widget app(Widget child, {double scale = 1.0}) => MaterialApp(
          theme: AppTheme.current,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: const Size(360, 740), textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: child),
            ),
          ),
        );

    testWidgets('canvas paints 250 booth boxes and taps the right one', (tester) async {
      final pins = <FloorPin>[
        for (var i = 0; i < 250; i++)
          _pin('b$i', 'A${i.toString().padLeft(3, '0')}', x: 0.03 + (i % 25) * 0.038, y: 0.05 + (i ~/ 25) * 0.09, w: 0.03, h: 0.05, ex: i.isEven ? 'x$i' : null),
        _pin('stage', 'Main stage', kind: PinKind.stage, x: 0.5, y: 0.97),
      ];
      final level = FloorLevel(id: 'L1', eventId: 'ev', name: 'Hall A', sort: 0, pins: pins);
      FloorPin? tapped;
      await tester.pumpWidget(app(SizedBox(
        width: 360,
        height: 600,
        child: FloorplanCanvas(
          level: level,
          onPinTap: (p) => tapped = p,
          partnerLogos: const {'b0': null, 'b2': null},
          highlightPinIds: const {'b4'},
          focus: const FloorplanFocus(Rect.fromLTWH(0.1, 0.1, 0.03, 0.05), 1),
        ),
      )));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      // Two partner logos as widgets; the boxes are painted, not widgets.
      expect(find.byType(PartnerLogoMarker), findsNWidgets(2));
      expect(find.byType(PinBadge), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BoothBoxPainter), findsOneWidget);

      // Reset zoom, then tap the middle of booth b30 (row 1, col 5).
      await tester.pumpWidget(app(SizedBox(width: 360, height: 600, child: FloorplanCanvas(key: const ValueKey('fresh'), level: level, onPinTap: (p) => tapped = p))));
      await tester.pump(const Duration(milliseconds: 600));
      final box = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BoothBoxPainter));
      final target = pins.firstWhere((p) => p.id == 'b30');
      await tester.tapAt(Offset(box.left + target.x * box.width, box.top + target.y * box.height));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped?.id, 'b30');
    });

    testWidgets('exhibitor row fits at text scale 1.3', (tester) async {
      final e = _ex('1', 'A very long exhibitor name that goes on and on Sdn Bhd', booths: const ['A019', 'A024', 'A025', 'A026'], category: 'Performance parts and accessories', partner: 'v');
      await tester.pumpWidget(app(ListView(children: [ExhibitorRow(exhibitor: e, onTap: () {})]), scale: 1.3));
      expect(tester.takeException(), isNull);
      expect(find.text('Partner'), findsOneWidget);
    });
  });
}
