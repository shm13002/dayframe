//
//  WeakScriptMessageHandler.swift
//  Dayframe
//
//  WKUserContentController keeps a strong reference to its message handlers, so a
//  coordinator registered directly would never be freed. This forwards through a
//  weak reference instead.
//

import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: WKScriptMessageHandler?

  init(_ target: WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
