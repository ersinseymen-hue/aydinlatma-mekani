import UserNotifications
import OneSignalExtension

class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var receivedRequest: UNNotificationRequest?
  private var bestAttemptContent: UNMutableNotificationContent?
  override func didReceive(_ request: UNNotificationRequest,
                          withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    receivedRequest = request
    bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
    if let content = bestAttemptContent {
      OneSignalExtension.didReceiveNotificationExtensionRequest(request, with: content, withContentHandler: contentHandler)
    } else { contentHandler(request.content) }
  }
  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttemptContent, let request = receivedRequest {
      OneSignalExtension.serviceExtensionTimeWillExpireRequest(request, with: content)
      handler(content)
    }
  }
}
