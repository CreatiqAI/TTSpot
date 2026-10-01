import Intents
import UserNotifications

/// Turns a chat push into an iOS Communication Notification: the sender's
/// avatar as the big picture with a small TT Spot badge on it, their name
/// (or my nickname for them) as the title, the message as the body.
///
/// Runs for every push that carries `mutable-content: 1` (set by
/// supabase/functions/push). Only `kind == "chat"` is changed; everything
/// else, and any failure, falls through to the push as sent (app icon,
/// title, body). Needs the Communication Notifications capability on the
/// app (Runner.entitlements) and INSendMessageIntent in NSUserActivityTypes.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var original: UNNotificationContent?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    original = request.content
    let content = request.content
    let info = content.userInfo
    // FCM puts the data keys at the top level of userInfo.
    guard (info["kind"] as? String) == "chat", !content.title.isEmpty else {
      finish(content)
      return
    }
    let avatar = (info["avatar"] as? String).flatMap { URL(string: $0) }
    loadImage(avatar) { [weak self] data in
      self?.communicate(content, info: info, imageData: data)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    if let content = original { finish(content) }
  }

  private func finish(_ content: UNNotificationContent) {
    guard let handler = contentHandler else { return }
    contentHandler = nil
    handler(content)
  }

  private func communicate(_ content: UNNotificationContent, info: [AnyHashable: Any], imageData: Data?) {
    let image = imageData.map { INImage(imageData: $0) }
    let group = (info["group"] as? String) == "1"
    let senderId = (info["sender_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? content.title
    let senderName = group ? ((info["sender_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? content.title) : content.title
    let conversationId = (info["conversation_id"] as? String) ?? senderId

    let sender = INPerson(
      personHandle: INPersonHandle(value: senderId, type: .unknown),
      nameComponents: nil,
      displayName: senderName,
      image: image,
      contactIdentifier: nil,
      customIdentifier: senderId
    )
    let me = INPerson(
      personHandle: INPersonHandle(value: "me", type: .unknown),
      nameComponents: nil,
      displayName: nil,
      image: nil,
      contactIdentifier: nil,
      customIdentifier: nil,
      isMe: true
    )
    let intent = INSendMessageIntent(
      recipients: group ? [me, sender] : [me],
      outgoingMessageType: .outgoingMessageText,
      content: content.body,
      speakableGroupName: group ? INSpeakableString(spokenPhrase: content.title) : nil,
      conversationIdentifier: conversationId,
      serviceName: nil,
      sender: sender,
      attachments: nil
    )
    if group, let image { intent.setImage(image, forParameterNamed: \.speakableGroupName) }

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate { [weak self] _ in
      do {
        let updated = try content.updating(from: intent)
        self?.finish(updated)
      } catch {
        self?.finish(content)
      }
    }
  }

  /// The avatar bytes, or nil after 6 s / on any error (the push still shows).
  private func loadImage(_ url: URL?, done: @escaping (Data?) -> Void) {
    guard let url, url.scheme == "https" else {
      done(nil)
      return
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 6
    URLSession.shared.dataTask(with: request) { data, response, _ in
      let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      done(ok ? data : nil)
    }.resume()
  }
}
