/// What's new, in member words. Newest first. Add a block for every build
/// that goes to a phone (see CHANGELOG.md for the developer-side log).
class ReleaseNote {
  const ReleaseNote({required this.version, required this.date, required this.title, required this.points});
  final String version;
  final String date;
  final String title;
  final List<String> points;
}

const kReleaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '0.3.11',
    date: '16 Sep 2026',
    title: 'Map sizing and a quick intro',
    points: [
      'Map markers follow the Waze standard: small dots when you look at the whole city, shapes as you zoom in, names up close.',
      'A four-slide intro after sign-in. Replay it from Settings → About.',
    ],
  ),
  ReleaseNote(
    version: '0.3.10',
    date: '16 Sep 2026',
    title: 'Call a friend',
    points: [
      'Call button on a friend\'s profile and in their chat: phone call or WhatsApp.',
      'Off by default. Turn on "Who can call me" in Settings to let friends see it.',
      'Emails from TT Spot got a clean new look.',
    ],
  ),
  ReleaseNote(
    version: '0.3.9',
    date: '15 Sep 2026',
    title: 'Every account, its own inbox',
    points: [
      'Switch to a club or partner and the tabs change: its page, its events, its chats, its account. Nothing mixes with your personal chats.',
      'Message a club from its page. The club replies as the club.',
      'Admin has Dashboard, Members (search and filters), Queues and Account, in the normal light look.',
      'Chat: + for attachments, tap the mic for a hold-to-speak bar, hosting card and HOST badge in meet chats, mute any chat.',
    ],
  ),
  ReleaseNote(
    version: '0.3.8',
    date: '15 Sep 2026',
    title: 'Who organises what',
    points: [
      'Anyone can plan a TT session for later, not just right now. It shows as a flag.',
      'Events (meets, convoys, track days) are hosted by car clubs and partners.',
      'Top spots earn the star by activity: 20 check-ins or 3 events in 90 days.',
      'Suggest a spot from the Create sheet or the Spots layer. 30 points when it goes live.',
      'Real Klang Valley venues on the map.',
    ],
  ),
  ReleaseNote(
    version: '0.3.7',
    date: '15 Sep 2026',
    title: 'A cleaner map',
    points: [
      'Small shapes instead of big cards: balloon = event, feather flag = TT session, badge = spot.',
      'Zoomed out you see only events, TT sessions and spots. Zoom in for people, closer for cars and names.',
      'A key on the left of the map explains the shapes.',
      'Colour a friend from the map list (the dot next to their name) or their profile.',
      'Sign-up no longer asks for an email code for now.',
    ],
  ),
  ReleaseNote(
    version: '0.3.6',
    date: '15 Sep 2026',
    title: 'Safer accounts',
    points: [
      'Sign-up now asks for a 6-digit code from your email.',
      'Every account needs a phone number and must accept the Terms once.',
      'Settings shows your email, phone and sign-in methods. Link Google to your account.',
      'This page: what changed in each update.',
    ],
  ),
  ReleaseNote(
    version: '0.3.5',
    date: '15 Sep 2026',
    title: 'Settings, admin, map colours',
    points: [
      'New Settings: notifications, map theme, privacy, Terms, delete account.',
      'Admin has its own account in the switcher.',
      'Map: you are red, friends blue, club purple, nearby grey. Give a friend a colour of your choice.',
      'Zoomed out, cars become small dots.',
      'TT now remembers the place you picked.',
    ],
  ),
  ReleaseNote(
    version: '0.3.4',
    date: '15 Sep 2026',
    title: 'TT now finds the spot',
    points: [
      'TT now fills in the nearest place and street from your GPS.',
      'Nearby radius up to 10 km.',
      'Map panel is white by day.',
    ],
  ),
  ReleaseNote(
    version: '0.3.3',
    date: '15 Sep 2026',
    title: 'Cleaner chats',
    points: [
      'Your bubbles are light grey, theirs white.',
      'Voice notes and videos in chat.',
    ],
  ),
  ReleaseNote(
    version: '0.3.0',
    date: '15 Sep 2026',
    title: 'Map v2',
    points: [
      'Your car and your friends\' cars on the map.',
      'Light map by day, dark after 7 pm.',
      'Choose who sees you: friends, friends + nearby (with a distance), everyone, or nobody.',
      'TT now: invite friends, pick how long, one radar ping every 5 seconds.',
      'Meet page: open in Waze or Google Maps, share on WhatsApp, copy link.',
    ],
  ),
  ReleaseNote(
    version: '0.2.x',
    date: '15 Sep 2026',
    title: 'Moments, chats, accounts',
    points: [
      'Moments with albums on your profile.',
      'Pin up to 3 chats, delete a chat, chat info page.',
      'Switch between your personal, club and partner accounts.',
      'Swipe back works everywhere on iPhone.',
    ],
  ),
];
