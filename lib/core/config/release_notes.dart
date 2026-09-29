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
    version: '0.3.40',
    date: '29 Sep 2026',
    title: 'Box shop',
    points: [
      'A proper blind box shop on the Cards page: the box up front, what is inside, your points against the price, one big button.',
      'The Create sheet and TT now have a close button.',
      'The map shows the six car cafes (plus partner shops); the old demo spots are gone.',
    ],
  ),
  ReleaseNote(
    version: '0.3.39',
    date: '29 Sep 2026',
    title: 'Create from the middle',
    points: [
      'The + in the middle of the tab bar opens Create, for your own account and for a club. The + buttons on Home and your profile are gone.',
      'TT NOW is the red button at the top of Create. The map bar only shows a TT chip while one is running.',
      'Moments moved to Chats: one row at the top with you and your friends, new moments in red rings.',
      'Home starts on the For you / Following switch.',
      'Grids load faster and use less data: new posts, cars and moments get a small preview picture.',
      'TT NOW finds the places around you from a new map source. If a place looks wrong, pin it on the map.',
      'Videos over 40 MB in chat or 25 MB in moments get a clear message instead of a failed upload.',
    ],
  ),
  ReleaseNote(
    version: '0.3.38',
    date: '29 Sep 2026',
    title: 'Your garage, on Home',
    points: [
      'Garage moved to Home (For you, Following, Garage): today\'s car up top with its stats, all your cars in a row, tap one to drive it today.',
      'Your profile is just you now: photo, stats, bio, and a small strip of your cars.',
      'Save spots: tap the bookmark on any spot. Saved spots always show on your map.',
      'The map finds spots for you: switching to Spots zooms out to your nearest ones, and a pill tells you how far the closest spot is.',
    ],
  ),
  ReleaseNote(
    version: '0.3.37',
    date: '29 Sep 2026',
    title: 'Organizer tools',
    points: [
      'Verified organizers get a toolkit for their meets: crew who can work the door, scheduled announcements, and a lucky draw with a big-screen reveal and prize-claim QR codes.',
      'Floorplans with levels: organizers upload each floor and pin zones, booths and the stage. Members tap where they are, scan a zone QR, and save where they parked.',
      'Event invite QR: newcomers scan, download and enter the event code at sign-up to join the meet.',
      'Your own referral code (six letters and numbers) with a share link, on My QR and in Me, Invite friends.',
      'Pick which car you are bringing to TT now, a meet or a check-in when you own more than one.',
      'Map: spots show on every layer, your own marker no longer disappears on iPhone, and a clearer What\'s on the map key.',
      'TiTi welcomes you before sign-in, car recognition is more accurate, no more plate blurring, and log out asks first.',
      'New card back, and a clearer Chats icon.',
    ],
  ),
  ReleaseNote(
    version: '0.3.36',
    date: '29 Sep 2026',
    title: 'Meet TiTi',
    points: [
      'TiTi the cone now walks you through sign-up: welcome, your ride (he reads the model off your photo while you watch), you, then a gift.',
      'Your first blind box opens at the end of sign-up. Shake the phone (or tap the box three times); it buzzes harder each time, cracks, and the card flips itself.',
      'A real box: the blind box is now the red TT Spot box with the ribbon, on the Cards page too.',
      'Camera and Gallery buttons go straight to the camera or your photos.',
      'Location is asked last, with TiTi explaining why.',
    ],
  ),
  ReleaseNote(
    version: '0.3.35',
    date: '28 Sep 2026',
    title: 'Big one',
    points: [
      'Map: opens on you, a Back to me button when you drift away, a glowing You marker with heading, cleaner spot and partner pins, fewer map labels.',
      'Sign-up starts with your car: snap a photo, we read the make, model, year and colour and blur the number plate before it is saved. Fix anything we got wrong.',
      'Car photo AI: the app now reads make, model, year and specs off your car photo when you add a car (editable). AI portraits are built but stay off for members until the renders match the photo; admins can try the eight styles from the car page.',
      'Check-ins: a card pops up when you are at a meet, hosts get a Who\'s here list to confirm arrivals (small meets) or an exceptions list (big meets), and the turnout report shows checked in, stayed 10+ min and confirmed by host.',
    ],
  ),
  ReleaseNote(
    version: '0.3.34',
    date: '28 Sep 2026',
    title: 'Your car up front',
    points: [
      'The Me page opens on your default car. Switch car from the photo when you own more than one.',
      'One row of tabs: Posts, Garage, Cards. Saved, liked and commented posts moved to the menu.',
      'The garage is a clean list with a Default badge; the default car is the one on the map and the one you go to meets with.',
    ],
  ),
  ReleaseNote(
    version: '0.3.33',
    date: '28 Sep 2026',
    title: 'Navigate without leaving',
    points: [
      'Directions now offers "Navigate in TT Spot": full-screen turn-by-turn with voice, live traffic and reroutes, inside the app.',
      'Waze and Google Maps are still there as before.',
      'Early version. Tell us how the routes compare to Waze on your usual roads.',
    ],
  ),
  ReleaseNote(
    version: '0.3.32',
    date: '28 Sep 2026',
    title: 'A new map',
    points: [
      'The map now runs on Mapbox: richer colours, real building shapes, a proper night look after 7 pm and smoother zooming.',
      'Every pin, car and moment is drawn the same way as before. Tell us if anything looks off.',
      'In-app navigation is next.',
    ],
  ),
  ReleaseNote(
    version: '0.3.31',
    date: '28 Sep 2026',
    title: 'Meet TiTi',
    points: [
      'The real card art is in: all seven cards starring TiTi the cone, including the secret Series 07 legendary with TypeOne.',
    ],
  ),
  ReleaseNote(
    version: '0.3.30',
    date: '28 Sep 2026',
    title: 'Cards on your profile',
    points: [
      'Every profile has a Cards tab: your collection at a glance, with Open box and Trade right there.',
      'Saved, Liked and Commented moved under the Posts tab on your own profile.',
      'Fixed: opening a box could fail on the first try.',
    ],
  ),
  ReleaseNote(
    version: '0.3.29',
    date: '28 Sep 2026',
    title: 'Blind box cards',
    points: [
      'Every member gets a blind box: tap it open, swipe to flip the card. 7 cards to collect (4 common, 2 rare, 1 legendary).',
      'More boxes cost points. Odds are shown in the app.',
      'Trade cards with friends, up to 9 a side. Offers land in Cards → Trades and in your activity.',
      'Prizes: spend cards on rewards from TT Spot or partners and show a QR at pickup. Cards never expire.',
      'Find it under Me → menu → Cards & blind boxes.',
    ],
  ),
  ReleaseNote(
    version: '0.3.28',
    date: '24 Sep 2026',
    title: 'Getting ready for the App Store',
    points: [
      'Sign in with Apple on iPhone.',
      'Report or block from anywhere: hold a chat message, or use the menu on a moment, post, comment, club or profile. Blocked members disappear from your chats too.',
      'Push notifications for messages, meet reminders, invites and club news (switch each kind off in Settings).',
      'Hosts get a turnout report after a meet: verified check-ins, show rate, first-timers, cars by make and model, arrival times. Share it with sponsors.',
      'Share meets, clubs, profiles, posts, spots and partner pages to WhatsApp or anywhere from the share button.',
      'Photos load faster and use less data: they are kept on your phone after the first view.',
      'The TT Spot logo is readable in dark mode (white instead of black).',
      'The app now has its own ID (my.ttspot.app). On Android, uninstall the old TT Spot once, then install this one and log in again.',
    ],
  ),
  ReleaseNote(
    version: '0.3.27',
    date: '18 Sep 2026',
    title: 'Dark mode fixes',
    points: [
      'Dark mode: the TT session card in Create, the current release card in About, selected product options, poll numbers and active chips in the post composer are all readable again.',
      'The ring around your profile photo matches the page in dark mode instead of showing white.',
    ],
  ),
  ReleaseNote(
    version: '0.3.26',
    date: '18 Sep 2026',
    title: 'Location check',
    points: [
      'Hold the locate button on the map to see what your phone is reporting: fix age, accuracy in metres, precise location on or off, and buttons to open the same coordinates in Google Maps or Apple Maps.',
      'Use my location works again (a Google place type had changed).',
    ],
  ),
  ReleaseNote(
    version: '0.3.25',
    date: '18 Sep 2026',
    title: 'Where you really are',
    points: [
      'TT now only fills in a place when you are actually at it (within 80 m): your condo, a mall, a workshop. A restaurant down the road is offered as a chip with its distance, never assumed.',
      'The map shows building names and footprints when you zoom in, so a pin lands on a building instead of blank ground.',
      'GPS on iPhone runs in the driving profile with navigation-grade accuracy.',
    ],
  ),
  ReleaseNote(
    version: '0.3.24',
    date: '18 Sep 2026',
    title: 'New map bar',
    points: [
      'The bar above the tabs is a solid panel: a red TT button with a car, a pill that says who and what is nearby (tap it for the lists), and a filter button.',
      'Pop-up sheets (TT now, filters, directions and the rest) now sit above the tab bar, so their buttons are never hidden.',
      'The map key lists only what is on the map right now.',
      'Dark mode: Maps and Copy link on a meet page, selected chips, and other black-on-dark spots are readable again.',
    ],
  ),
  ReleaseNote(
    version: '0.3.23',
    date: '18 Sep 2026',
    title: 'Tidier map toolbar',
    points: [
      'The map toolbar is built like the tab bar: TT now on the left on every layer, what is on the map in the middle, an open button on the right with the count of moments today.',
      'Tap the map to close the list.',
    ],
  ),
  ReleaseNote(
    version: '0.3.22',
    date: '18 Sep 2026',
    title: 'Cleaner map, truer location',
    points: [
      'The bottom of the map is one slim glass row: TT now, who is on the map, today\'s moments. Pull up or tap a chip for the lists.',
      'Your pin follows live GPS and shows a ring for how sure the phone is. Bad fixes are ignored; the locate button gets a fresh one.',
      'iPhone: if location is approximate, a banner offers to switch on Precise Location.',
      'The map key folds away after the first look.',
    ],
  ),
  ReleaseNote(
    version: '0.3.21',
    date: '17 Sep 2026',
    title: 'Official and underground clubs',
    points: [
      'Clubs are Official (meet notifications, plan any distance ahead, gold map badge, no member limit, 10 % bonus points for the president) or Underground (7 days ahead, 100 members, a club garage that pings the crew).',
      'Club roles: President, Vice President, Secretary. Every club has a most-active leaderboard.',
      'Partners: SSM and shop photo required, shops in Johor, Penang or KL. Partners see every upcoming meet to sponsor and every car club with what its members drive. Partner events tell everyone and get their own map badge.',
      'Save any meet with the bookmark and get a reminder before it starts.',
    ],
  ),
  ReleaseNote(
    version: '0.3.20',
    date: '17 Sep 2026',
    title: 'Dark mode for the whole app',
    points: [
      'Settings → Appearance: Auto (light 7 am to 7 pm, dark at night), Always light, Always dark. Every page follows, not only the map.',
      'A clear Directions button on partner pages, with a Waze / Google Maps choice and a proper confirm sheet.',
      'The map list no longer hides under the tab bar.',
      'Admin overview rebuilt: right now, decisions, 7-day trends, community and rewards totals, top spots, newest members.',
    ],
  ),
  ReleaseNote(
    version: '0.3.19',
    date: '17 Sep 2026',
    title: 'Glass, motion, and club requests',
    points: [
      'Frosted glass tab bar with a sliding highlight; tabs fade in; buttons squeeze when pressed. Map controls are glass too.',
      'Tapping a pin from far out glides in first, then opens it. Your own dot always shows.',
      'Moments are photo cards now, not rings. Car of the week is gone from the feed.',
      'Ask to join a club. The owner and admins approve or decline from the club page.',
    ],
  ),
  ReleaseNote(
    version: '0.3.18',
    date: '17 Sep 2026',
    title: 'Map pins that scale',
    points: [
      'Pins grow as you zoom in and shrink as you zoom out, instead of jumping between three sizes.',
      'Zoomed out past city level, nobody is drawn, not even you. Zoom in and people come back.',
    ],
  ),
  ReleaseNote(
    version: '0.3.17',
    date: '17 Sep 2026',
    title: 'Partner page, cleaner',
    points: [
      'Partner pages have a cover, the logo, and Info · Products · Vouchers · Posts · Events sections you can jump to.',
      'Partner shops are a signboard on the map and moments are a polaroid, so neither looks like a person.',
      'Logo and shop changes show on the partner page straight away.',
    ],
  ),
  ReleaseNote(
    version: '0.3.16',
    date: '17 Sep 2026',
    title: 'Partner tabs and variant photos',
    points: [
      'Partner accounts get five tabs: Overview, Products, Vouchers, Chats, Account. The overview is new: quick actions, a setup checklist and 30-day numbers.',
      'Variant options can carry their own price and photo. Picking one switches the price and the photo.',
      'Preview a product as a member before saving.',
      'Waze, Google Maps, WhatsApp and calls ask before leaving the app.',
      'Partner shops show on every map layer, not only Spots.',
    ],
  ),
  ReleaseNote(
    version: '0.3.15',
    date: '17 Sep 2026',
    title: 'Partner shops, and a pile of fixes',
    points: [
      'Partners can show up to 5 products with variants. Members browse them on the partner page and message the shop.',
      'Vouchers can apply to one product. Rewards has a Partners tab listing every shop, nearest first.',
      'Waze and WhatsApp no longer open the browser after you tap Cancel.',
      'Phone numbers format themselves as you type. Usernames are checked while you type.',
      'Likes and saves pop. Tapping the comment bubble on a post jumps to the comment box.',
      'Only the owner can post from a car page. Tagged cars, spots and meets on posts are links.',
    ],
  ),
  ReleaseNote(
    version: '0.3.14',
    date: '16 Sep 2026',
    title: 'Partners, round two',
    points: [
      'Opening hours are picked per day, and the partner page shows "Open now" or when it opens next.',
      'Partners can post to the feed as the business. Posts show on the partner page.',
      'Partner dashboard shows page views, check-ins and voucher claims for the last 30 days.',
    ],
  ),
  ReleaseNote(
    version: '0.3.13',
    date: '16 Sep 2026',
    title: 'Partner pages and shops on the map',
    points: [
      'Every partner has a page: logo, photos, hours, address with Waze and Maps, vouchers, events, Message and WhatsApp.',
      'Partner shops sit on the Spots layer with their logo. Check in there for points.',
      'Partners: add opening hours and up to six photos in Edit shop.',
    ],
  ),
  ReleaseNote(
    version: '0.3.12',
    date: '16 Sep 2026',
    title: 'Partner fixes',
    points: [
      'Shop address in the partner form now searches Google Places.',
      'Approved as a partner or club? It shows the moment you open the account switcher, no restart.',
      'Admin counts refresh when you switch to the admin account.',
      'Partner statement shows only your own redemptions.',
    ],
  ),
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
