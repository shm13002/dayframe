import XCTest

@testable import Dayflow

final class JarvisListenerTests: XCTestCase {
  func testStopsAfterTrailingSilence() {
    var gate = JarvisSilenceGate()
    XCTAssertEqual(gate.feed(rms: 0.1, duration: 0.5), .keepListening)
    XCTAssertEqual(gate.feed(rms: 0.001, duration: 0.6), .keepListening)
    XCTAssertEqual(gate.feed(rms: 0.001, duration: 0.6), .done)
  }

  func testSpeechResetsTheSilenceClock() {
    var gate = JarvisSilenceGate()
    _ = gate.feed(rms: 0.1, duration: 0.2)
    _ = gate.feed(rms: 0.0, duration: 1.0)
    XCTAssertEqual(gate.feed(rms: 0.1, duration: 0.2), .keepListening)
    XCTAssertEqual(gate.feed(rms: 0.0, duration: 1.0), .keepListening)
  }

  func testGivesUpWhenNobodySpeaks() {
    var gate = JarvisSilenceGate()
    XCTAssertEqual(gate.feed(rms: 0.0, duration: 5.9), .keepListening)
    XCTAssertEqual(gate.feed(rms: 0.0, duration: 0.2), .nothingSaid)
  }

  func testLongSpeechEndsAtTheCap() {
    var gate = JarvisSilenceGate()
    XCTAssertEqual(gate.feed(rms: 0.5, duration: 46), .done)
  }

  func testWAVHeader() {
    let wav = JarvisWAV.encode([0, 1, -1])
    XCTAssertEqual(wav.count, 44 + 6)
    XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
    XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
    let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    XCTAssertEqual(UInt32(littleEndian: rate), 16000)
    let size = wav[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    XCTAssertEqual(UInt32(littleEndian: size), 6)
  }
}
