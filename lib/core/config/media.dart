// Photo and video sizes for uploads. Storage egress is billed per GB served,
// so nothing goes up bigger than where it is shown.

/// Longest side for pictures that show small (avatars, club and partner
/// logos, poll options: 96 px or less on screen).
const kSmallPhotoSide = 512.0;

/// Grid thumbnails (see lib/core/utils/thumbnails.dart): shortest side and
/// JPEG quality.
const kThumbSide = 480;
const kThumbQuality = 75;

/// Cache-Control for storage files that are never overwritten (a new path per
/// upload): one year, so the CDN and the phone keep them instead of asking
/// again every hour (the default is 3600).
const kImmutableCacheControl = '31536000';

/// Videos. `maxDuration` is not enforced for library picks on every platform,
/// so the file size is checked after picking too. The chat-media bucket (chat
/// and moment videos) refuses anything over 50 MB.
const kChatVideoMaxDuration = Duration(seconds: 60);
const kChatVideoMaxMb = 40;
const kStoryVideoMaxDuration = Duration(seconds: 30);
const kStoryVideoMaxMb = 25;

/// Photos and videos sent together from the chat preview.
const kChatMediaMaxItems = 10;
