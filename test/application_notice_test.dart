import 'package:car_meet/core/router/app_router.dart';
import 'package:car_meet/features/social/domain/application_notice.dart';
import 'package:car_meet/features/social/domain/notification.dart';
import 'package:car_meet/features/social/presentation/activity_screen.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(String body) => AppNotification(id: 'n1', type: NotificationType.partner, body: body, read: false, createdAt: DateTime(2026, 10, 7));

void main() {
  group('application decisions in Activity', () {
    test('partner approved: name, short copy, opens the partner dashboard', () {
      expect(activityText(_n('approved:12V Sdn Bhd')), ('12V Sdn Bhd is approved. Your partner tools are ready.', Routes.vendor));
    });

    test('partner rejected: the note, opens the application page', () {
      expect(activityText(_n('rejected:SSM number does not match the shop name')),
          ("Your partner application wasn't approved. Note: SSM number does not match the shop name", Routes.partnerApply));
      expect(activityText(_n('rejected:no reason given')), ("Your partner application wasn't approved.", Routes.partnerApply));
    });

    test('car club and organizer decisions', () {
      expect(activityText(_n('approved-club:Myvi Klang')), ('Myvi Klang is approved. Create your club and invite members.', Routes.createClub));
      expect(activityText(_n('rejected-club:Please add your club page')), ("Your car club application wasn't approved. Note: Please add your club page", Routes.clubApply));
      expect(activityText(_n('approved-organizer:KL Night Runs')), ('KL Night Runs is approved. Your organizer tools are ready.', Routes.organizerApply));
      expect(activityText(_n('rejected-organizer:no reason given')), ("Your organizer application wasn't approved.", Routes.organizerApply));
    });

    test('admins see the new application and open the queue', () {
      expect(activityText(_n('applied:12V Sdn Bhd')), ('applied to be a partner: 12V Sdn Bhd', Routes.adminPartners));
      expect(activityText(_n('applied-club:Myvi Klang')), ('applied to run a car club: Myvi Klang', Routes.adminPartners));
      expect(activityText(_n('applied-organizer:KL Night Runs')), ('applied to be a verified organizer: KL Night Runs', Routes.adminPartners));
    });

    test('a note with a colon stays whole; unknown bodies pass through', () {
      expect(ApplicationNotice.parse('rejected:Hours: please add them')!.text, 'Hours: please add them');
      expect(ApplicationNotice.parse('something else'), isNull);
      expect(ApplicationNotice.parse('approved-shop:X'), isNull);
      expect(activityText(_n('Welcome aboard')), ('Welcome aboard', null));
    });
  });
}
