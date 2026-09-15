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
