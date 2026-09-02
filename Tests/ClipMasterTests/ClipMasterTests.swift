import XCTest
@testable import ClipMaster

final class ClipMasterTests: XCTestCase {
    func testEDLNetDurationCalculation() {
        let clip = ClipDecision(
            id: "clip_01",
            title: "Test Clip",
            viralScore: 95,
            hook: "Un gancho brutal...",
            timeRange: TimeRange(start: 10.0, end: 40.0), // 30s
            cutSegments: [
                CutSegment(start: 15.0, end: 18.0, reason: "silence_gap"), // 3s
                CutSegment(start: 25.0, end: 27.0, reason: "bad_take_retry") // 2s
            ],
            highlightWords: [
                HighlightWord(word: "brutal", timestamp: 11.2, color: "#FF3B30", sfx: "impact")
            ]
        )

        // 30s total - 3s - 2s = 25s neto
        XCTAssertEqual(clip.netDuration, 25.0, accuracy: 0.001)
    }

    func testKeepSegmentsCalculation() {
        let renderEngine = VideoRenderEngine()
        let totalRange = TimeRange(start: 0.0, end: 30.0)
        let cuts = [
            CutSegment(start: 5.0, end: 8.0, reason: "filler"),
            CutSegment(start: 15.0, end: 20.0, reason: "silence")
        ]

        let keep = renderEngine.calculateKeepSegments(totalRange: totalRange, cutSegments: cuts)

        XCTAssertEqual(keep.count, 3)
        XCTAssertEqual(keep[0].start, 0.0)
        XCTAssertEqual(keep[0].end, 5.0)

        XCTAssertEqual(keep[1].start, 8.0)
        XCTAssertEqual(keep[1].end, 15.0)

        XCTAssertEqual(keep[2].start, 20.0)
        XCTAssertEqual(keep[2].end, 30.0)
    }

    func testAudioLevelAnalyzerRMS() {
        let analyzer = AudioLevelAnalyzer()
        // Crear señal de prueba seno a amplitud 0.5
        var testSamples = [Float](repeating: 0.0, count: 1600) // 100ms a 16kHz
        for i in 0..<testSamples.count {
            testSamples[i] = 0.5 * sin(Float(i) * 0.1)
        }

        let windows = analyzer.analyzeEnergyProfile(samples: testSamples, sampleRate: 16000, windowDurationMs: 100)
        XCTAssertEqual(windows.count, 1)
        XCTAssertGreaterThan(windows[0].rms, 0.2)
        XCTAssertGreaterThan(windows[0].decibels, -15.0)
    }
}
