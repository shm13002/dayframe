import XCTest

@testable import Dayflow

final class JarvisVoiceTests: XCTestCase {
  func testShortSentencesRideTogether() {
    XCTAssertEqual(
      JarvisSpeechText.pieces("Good morning. You have three meetings."),
      ["Good morning. You have three meetings."])
  }

  func testEveryPieceFitsTheServerLimit() {
    let long = "Word " + Array(repeating: "word", count: 299).joined(separator: " ") + "."
    let pieces = JarvisSpeechText.pieces("Hello. " + long + " Done.")
    XCTAssertTrue(pieces.allSatisfy { $0.count <= JarvisSpeechText.maxPiece })
    XCTAssertEqual(pieces.first, "Hello.")
    XCTAssertEqual(pieces.last, "Done.")
    XCTAssertEqual(pieces.joined(separator: " ").split(separator: " ").count, 302)
  }

  func testMarkdownAndLinksAreNotReadAloud() {
    let text =
      "**Done.** See [the report](https://x.y/z) or https://a.b/c.\n```\nls -la\n```\n- one"
    XCTAssertEqual(
      JarvisSpeechText.speakable(text), "Done. See the report or a link one")
  }

  func testNothingToSay() {
    XCTAssertEqual(JarvisSpeechText.pieces("```\ncode only\n```"), [])
  }

  private func client(statuses: [Int], token: String? = String(repeating: "t", count: 40))
    -> (JarvisVoiceClient, () -> [URLRequest])
  {
    final class Box: @unchecked Sendable {
      var statuses: [Int]
      var requests: [URLRequest] = []
      init(_ s: [Int]) { statuses = s }
    }
    let box = Box(statuses)
    var client = JarvisVoiceClient()
    client.token = { token }
    client.busyRetries = 2
    client.send = { request in
      box.requests.append(request)
      let status = box.statuses.isEmpty ? 200 : box.statuses.removeFirst()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      return (Data("RIFF".utf8), response)
    }
    return (client, { box.requests })
  }

  func testSendsTokenAndTheServersExactBody() async throws {
    let (client, requests) = client(statuses: [200])
    let wav = try await client.wav(for: "Hello there.")
    XCTAssertEqual(wav, Data("RIFF".utf8))
    let request = try XCTUnwrap(requests().first)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Authorization"),
      "Bearer " + String(repeating: "t", count: 40))
    XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    XCTAssertEqual(body["text"] as? String, "Hello there.")
    XCTAssertEqual(body["voice"] as? String, "jarvis")
    XCTAssertEqual(body["steps"] as? Int, 32)
    XCTAssertEqual(body.count, 3)
  }

  func testPiperSendsOnlyTextAndDoesNotRetry() async throws {
    let (piper, requests) = client(statuses: [429, 200])
    var fast = piper
    fast.engine = .piper
    do {
      _ = try await fast.wav(for: "Hello there.")
      XCTFail("expected busy")
    } catch {
      XCTAssertEqual(error as? JarvisVoiceClient.Failure, .busy)
    }
    let request = try XCTUnwrap(requests().first)
    XCTAssertEqual(request.url?.port, 5056)
    XCTAssertEqual(request.timeoutInterval, 3)
    XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    XCTAssertEqual(body["text"] as? String, "Hello there.")
    XCTAssertEqual(body.count, 1)
    XCTAssertEqual(requests().count, 1)
  }

  func testLiveRouteSkipsTheSlowClone() {
    XCTAssertEqual(JarvisVoiceRoute.steps(mode: .live), [.cache, .piper, .mac])
    XCTAssertEqual(
      JarvisVoiceRoute.steps(mode: .notice), [.cache, .cloned, .piper, .mac])
  }

  func testFirstAudioIsMeasuredFromSpeakToPlay() {
    let asked = Date(timeIntervalSince1970: 1_000)
    let played = asked.addingTimeInterval(0.29)
    XCTAssertEqual(JarvisVoiceRoute.firstAudioMs(from: asked, to: played), 290)
    XCTAssertEqual(JarvisVoiceRoute.firstAudioMs(from: played, to: asked), 0)
  }

  func testBusyIsRetriedThenGivesUp() async {
    let (retrying, retryRequests) = client(statuses: [429, 200])
    let wav = try? await retrying.wav(for: "Hi.")
    XCTAssertNotNil(wav)
    XCTAssertEqual(retryRequests().count, 2)

    let (stuck, _) = client(statuses: [429, 429, 429])
    do {
      _ = try await stuck.wav(for: "Hi.")
      XCTFail("expected busy")
    } catch {
      XCTAssertEqual(error as? JarvisVoiceClient.Failure, .busy)
    }
  }

  func testFailuresAreNamed() async {
    for (status, expected) in [
      (401, JarvisVoiceClient.Failure.unauthorized), (422, .unverified), (503, .failed(503)),
    ] {
      let (c, _) = client(statuses: [status])
      do {
        _ = try await c.wav(for: "Hi.")
        XCTFail("expected \(expected)")
      } catch {
        XCTAssertEqual(error as? JarvisVoiceClient.Failure, expected)
      }
    }
    let (noToken, requests) = client(statuses: [], token: nil)
    do {
      _ = try await noToken.wav(for: "Hi.")
      XCTFail("expected noToken")
    } catch {
      XCTAssertEqual(error as? JarvisVoiceClient.Failure, .noToken)
    }
    XCTAssertTrue(requests().isEmpty)
  }
}

final class JarvisPhraseCacheTests: XCTestCase {
  func testSameLineSameKey() {
    XCTAssertEqual(JarvisPhraseCache.key("On it!"), JarvisPhraseCache.key("  on   it. "))
    XCTAssertEqual(JarvisPhraseCache.key("I’ve finished."), JarvisPhraseCache.key("i've finished"))
    XCTAssertNotEqual(JarvisPhraseCache.key("Done."), JarvisPhraseCache.key("All done."))
  }

  func testStoresAndReads() throws {
    var cache = JarvisPhraseCache()
    cache.folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("jarvis-cache-\(UUID().uuidString)")
    XCTAssertNil(cache.wav(for: "Done."))
    cache.store(Data("RIFF".utf8), for: "Done.")
    XCTAssertEqual(cache.wav(for: "done"), Data("RIFF".utf8))
    try? FileManager.default.removeItem(at: cache.folder)
  }
}
