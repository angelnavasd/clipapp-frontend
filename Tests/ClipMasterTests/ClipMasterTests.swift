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

    // MARK: - F3 FaceTracking helpers puros

    func testMedianRectRejectsOutliers() {
        let good = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25)
        let rects = [good, good, good, CGRect(x: 0.9, y: 0.9, width: 0.05, height: 0.05)]
        let median = FaceTrackingService.medianRect(of: rects)
        XCTAssertNotNil(median)
        // La mediana debe seguir cerca del cluster bueno, no del outlier
        XCTAssertEqual(median!.midX, good.midX, accuracy: 0.03)
        XCTAssertEqual(median!.midY, good.midY, accuracy: 0.03)
    }

    func testMedianRectEmptyReturnsNil() {
        XCTAssertNil(FaceTrackingService.medianRect(of: []))
    }

    func testSmoothCentersDeadzoneHoldsStill() {
        // Micro-movimientos dentro de la deadzone no deben mover el encuadre
        let base = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2)
        let jitter = CGRect(x: 0.401, y: 0.301, width: 0.2, height: 0.2)
        let hits = [(0.0, base), (0.5, jitter), (1.0, jitter)]
        let sm = FaceTrackingService.smoothCenters(hits, lerpFactor: 0.08, deadzone: 0.035)
        XCTAssertEqual(sm.count, 3)
        XCTAssertEqual(sm[1].x, sm[0].x, accuracy: 0.0001)
        XCTAssertEqual(sm[1].y, sm[0].y, accuracy: 0.0001)
    }

    func testSmoothCentersFollowsLargeMove() {
        let a = CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.2)
        var hits: [(Double, CGRect)] = [(0.0, a)]
        for i in 1...30 { hits.append((Double(i) * 0.5, b)) }
        let sm = FaceTrackingService.smoothCenters(hits, lerpFactor: 0.15, deadzone: 0.01)
        // Tras 30 pasos debe haberse acercado sustancialmente al objetivo
        XCTAssertGreaterThan(sm.last!.x, 0.6)
    }

    func testIsScreenShareThreshold() {
        XCTAssertTrue(FaceTrackingService.isScreenShare(face: CGRect(x: 0.8, y: 0.75, width: 0.15, height: 0.2)))
        XCTAssertFalse(FaceTrackingService.isScreenShare(face: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4)))
    }

    // MARK: - F4 FaceCropCalculator (preview == export)

    func testCropCentersFaceHorizontally16x9() {
        // Source 1920x1080 -> target 1080x1920: scale por altura = 1.777, scaledW = 3413
        // Cara a la derecha (x=0.8): offsetX debe ser negativo (paneamos a la derecha)
        let t = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            center: CGPoint(x: 0.8, y: 0.5),
            mode: .autoFaceTrack
        )
        XCTAssertLessThan(t.tx, 0)
        // Cara a la izquierda: offset hacia el otro lado
        let t2 = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            center: CGPoint(x: 0.2, y: 0.5),
            mode: .autoFaceTrack
        )
        XCTAssertGreaterThan(t2.tx, t.tx)
    }

    func testCropClampsAtEdges() {
        let target = CGSize(width: 1080, height: 1920)
        // Cara pegada al borde izquierdo: no debe mostrar barras negras (offsetX <= 0)
        let left = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: target,
            center: CGPoint(x: 0.0, y: 0.5),
            mode: .autoFaceTrack
        )
        XCTAssertLessThanOrEqual(left.tx, 0.001)
        // Cara pegada al borde derecho: offsetX >= targetW - scaledW
        let scale = target.height / 1080.0
        let minTx = target.width - 1920.0 * scale
        let right = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: target,
            center: CGPoint(x: 1.0, y: 0.5),
            mode: .autoFaceTrack
        )
        XCTAssertGreaterThanOrEqual(right.tx, minTx - 1.0)
    }

    func testCropVerticalSourceUsesWidthScale() {
        // Source vertical 1080x1920 -> encaja exacto, transform ~identidad en escala
        let t = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1080, height: 1920),
            center: CGPoint(x: 0.5, y: 0.4),
            mode: .autoFaceTrack
        )
        XCTAssertEqual(t.a, 1.0, accuracy: 0.001)
        XCTAssertEqual(t.d, 1.0, accuracy: 0.001)
    }

    func testCropZoomForFarFace() {
        // Cara chica (PiP) -> ventana menor que el frame (más escala)
        let noZoom = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            center: CGPoint(x: 0.5, y: 0.5),
            faceWidth: 0.4,
            mode: .autoFaceTrack
        )
        let zoom = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080),
            center: CGPoint(x: 0.5, y: 0.5),
            faceWidth: 0.08,
            mode: .autoFaceTrack
        )
        XCTAssertGreaterThan(zoom.a, noZoom.a)
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: nil), 1.0)
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.5), 1.0, accuracy: 0.001)
    }

    func testPreviewLayoutMatchesExport() {
        // Misma entrada -> preview y export deben coincidir en escala y proporción de offset
        let src = CGSize(width: 1920, height: 1080)
        let container = CGSize(width: 300, height: 533)
        let target = CGSize(width: 1080, height: 1920)
        let center = CGPoint(x: 0.7, y: 0.45)
        let layout = FaceCropCalculator.previewLayout(containerSize: container, sourceSize: src, center: center, faceWidth: nil)
        let export = FaceCropCalculator.exportTransform(sourceSize: src, targetSize: target, center: center, mode: .autoFaceTrack)
        // La escala debe ser proporcional (mismo aspect-fill en ambos espacios)
        let previewScale = layout.size.width / src.width
        XCTAssertEqual(previewScale, layout.size.height / src.height, accuracy: 0.001)
        let exportScale = export.a
        XCTAssertEqual(layout.size.width / container.width, 3413.0 / 1080.0 * (container.width / container.width), accuracy: 2.0)
        // El offset relativo (fracción del tamaño) debe coincidir entre preview y export
        let previewFracX = layout.offset.width / layout.size.width
        let exportFracX = export.tx / (src.width * exportScale)
        XCTAssertEqual(previewFracX, exportFracX, accuracy: 0.002)
        _ = previewScale
    }

    func testSplitCropRectWithinBounds() {
        let src = CGSize(width: 1920, height: 1080)
        for cx in [0.0, 0.15, 0.5, 0.85, 1.0] {
            let r = FaceCropCalculator.splitBottomCropRect(sourceSize: src, center: CGPoint(x: cx, y: 0.8))
            XCTAssertGreaterThanOrEqual(r.origin.x, 0)
            XCTAssertLessThanOrEqual(r.maxX, src.width + 0.001)
            XCTAssertGreaterThanOrEqual(r.origin.y, 0)
            XCTAssertLessThanOrEqual(r.maxY, src.height + 0.001)
        }
    }

    func testSplitCropLlenaSuZonaSinBandas() {
        // Zona inferior 1080 x (1920*0.45=864): el crop debe salir con ese aspect
        let zoneAspect = 1080.0 / (1920.0 * 0.45)
        let r = FaceCropCalculator.splitBottomCropRect(
            sourceSize: CGSize(width: 1920, height: 1080),
            center: CGPoint(x: 0.85, y: 0.8),
            targetAspect: zoneAspect)
        XCTAssertEqual(r.width / r.height, zoneAspect, accuracy: 0.01)
    }

    // MARK: - F5 Resolución conjunta editorial-visual

    private func makeTrack(face: CGRect?, confidence: Float = 0.9, rate: Double = 1.0, pip: Bool = false, faces: Int = 1) -> BeatFaceTrack {
        BeatFaceTrack(beatIndex: 0, start: 0, end: 10, samples: [], averageFace: face, confidence: confidence, maxFaceCount: faces, detectionRate: rate, isScreenShare: pip)
    }

    func testResolveHookConCaraSigueRostro() {
        let engine = SceneLayoutEngine.shared
        let face = CGRect(x: 0.6, y: 0.3, width: 0.2, height: 0.25)
        let r = engine.resolveClipFraming(hookNeedsFace: true, hookTrack: makeTrack(face: face), anyScreenShare: false, anyMultiSpeaker: false)
        XCTAssertEqual(r.mode, .autoFaceTrack)
        XCTAssertEqual(r.centerX, face.midX, accuracy: 0.001)
    }

    func testResolveHookSinCaraVaAFondoCompleto() {
        let engine = SceneLayoutEngine.shared
        let r = engine.resolveClipFraming(hookNeedsFace: true, hookTrack: makeTrack(face: nil, confidence: 0, rate: 0), anyScreenShare: false, anyMultiSpeaker: false)
        XCTAssertEqual(r.mode, .blurredBackground)
    }

    func testResolveScreenShareVaASplit() {
        let engine = SceneLayoutEngine.shared
        let pip = CGRect(x: 0.8, y: 0.75, width: 0.15, height: 0.18)
        let r = engine.resolveClipFraming(hookNeedsFace: false, hookTrack: makeTrack(face: pip, pip: true), anyScreenShare: true, anyMultiSpeaker: false)
        XCTAssertEqual(r.mode, .splitScreen)
    }

    func testResolveMultiSpeakerAbrePlano() {
        let engine = SceneLayoutEngine.shared
        let face = CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.25)
        let r = engine.resolveClipFraming(hookNeedsFace: true, hookTrack: makeTrack(face: face, faces: 2), anyScreenShare: false, anyMultiSpeaker: true)
        XCTAssertEqual(r.centerX, 0.5, accuracy: 0.001)
        XCTAssertNil(r.faceWidth)
    }

    func testResolveConfianzaBajaNoPersigue() {
        let engine = SceneLayoutEngine.shared
        let face = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.25)
        let r = engine.resolveClipFraming(hookNeedsFace: true, hookTrack: makeTrack(face: face, confidence: 0.2, rate: 0.2), anyScreenShare: false, anyMultiSpeaker: false)
        XCTAssertEqual(r.mode, .blurredBackground)
    }

    func testResolveUsaMejorBeatConCaraAunqueHookNoTenga() {
        let engine = SceneLayoutEngine.shared
        let hook = makeTrack(face: nil, confidence: 0, rate: 0)
        let face = CGRect(x: 0.65, y: 0.3, width: 0.2, height: 0.25)
        let later = BeatFaceTrack(beatIndex: 1, start: 20, end: 30, samples: [], averageFace: face, confidence: 0.9, maxFaceCount: 1, detectionRate: 0.9, isScreenShare: false)
        let r = engine.resolveClipFraming(hookNeedsFace: true, hookTrack: hook, allTracks: [hook, later], anyScreenShare: false, anyMultiSpeaker: false)
        XCTAssertEqual(r.mode, .autoFaceTrack)
        XCTAssertEqual(r.centerX, face.midX, accuracy: 0.001)
    }

    // MARK: - FIX-regresión: outliers y zoom

    func testRejectOutliersDropsCaraEnPantalla() {
        struct H { let rect: CGRect; let conf: Float }
        let real = H(rect: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25), conf: 0.95)
        // Falso positivo: carita en la pantalla compartida, lejos y chica
        let fake = H(rect: CGRect(x: 0.85, y: 0.8, width: 0.08, height: 0.1), conf: 0.6)
        let hits = [real, real, real, fake]
        let kept = FaceTrackingService.rejectOutliers(hits, rect: { $0.rect }, confidence: { $0.conf })
        XCTAssertEqual(kept.count, 3)
        let median = FaceTrackingService.medianRect(of: kept.map(\.rect))
        XCTAssertEqual(median!.midX, real.rect.midX, accuracy: 0.01)
    }

    func testRejectOutliersKeepsAnchorWhenAllFar() {
        struct H { let rect: CGRect; let conf: Float }
        let a = H(rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), conf: 0.9)
        let b = H(rect: CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1), conf: 0.5)
        let kept = FaceTrackingService.rejectOutliers([a, b], rect: { $0.rect }, confidence: { $0.conf })
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].rect.midX, a.rect.midX, accuracy: 0.001)
    }

    func testWindowHeightFraction() {
        // PiP (cara 0.10) -> 0.74 (primer plano seguro sin pixelar);
        // Hablante a cámara (0.18+) -> 1.0 (aspect-fill estándar sin sobre-zoom).
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.10), 0.74, accuracy: 0.001)
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.20), 1.0, accuracy: 0.001)
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.30), 1.0, accuracy: 0.001)
        XCTAssertEqual(FaceCropCalculator.windowHeightFraction(faceWidth: nil), 1.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.02), 0.74)
        XCTAssertLessThanOrEqual(FaceCropCalculator.windowHeightFraction(faceWidth: 0.9), 1.0)
    }

    func testClipFramingFallbackEsCentroNeutro() {
        let f = ClipFraming.fallback
        XCTAssertEqual(f.mode, .autoFaceTrack)
        XCTAssertEqual(f.centerX, 0.5, accuracy: 0.001)
        XCTAssertTrue(f.beatCenters.isEmpty)
    }

    // MARK: - Prueba de contención 9:16 (el crop siempre cubre el contenedor)

    func testPreviewLayoutSiempreCubreElContenedor() {
        let container = CGSize(width: 300, height: 533.33)
        let sources = [
            CGSize(width: 1920, height: 1080), // 16:9
            CGSize(width: 1080, height: 1920), // 9:16 vertical
            CGSize(width: 1440, height: 1080), // 4:3
            CGSize(width: 1080, height: 1080), // 1:1
            CGSize(width: 2560, height: 1080), // ultrawide
            CGSize(width: 1080, height: 1920), // retrato con rotación
        ]
        for src in sources {
            for cx in [0.0, 0.25, 0.5, 0.75, 1.0] {
                for fw in [nil, 0.1, 0.3] as [CGFloat?] {
                    let layout = FaceCropCalculator.previewLayout(
                        containerSize: container, sourceSize: src,
                        center: CGPoint(x: cx, y: 0.45), faceWidth: fw)
                    XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite,
                        "NaN en size src=\(src) cx=\(cx)")
                    XCTAssertTrue(layout.offset.width.isFinite && layout.offset.height.isFinite,
                        "NaN en offset src=\(src) cx=\(cx)")
                    XCTAssertGreaterThanOrEqual(layout.size.width, container.width - 0.5,
                        "no cubre ancho src=\(src) cx=\(cx)")
                    XCTAssertGreaterThanOrEqual(layout.size.height, container.height - 0.5,
                        "no cubre alto src=\(src) cx=\(cx)")
                    XCTAssertLessThanOrEqual(layout.offset.width, 0.5)
                    XCTAssertGreaterThanOrEqual(layout.offset.width, container.width - layout.size.width - 0.5)
                }
            }
        }
    }

    func testExportTransformSiempreFinito() {
        let target = CGSize(width: 1080, height: 1920)
        let badSizes = [CGSize.zero, CGSize(width: 0, height: 1080), CGSize(width: -5, height: 100)]
        for src in badSizes {
            let t = FaceCropCalculator.exportTransform(sourceSize: src, targetSize: target,
                center: CGPoint(x: 0.5, y: 0.5), mode: .autoFaceTrack)
            XCTAssertTrue(t.isIdentity, "tamaño inválido debe dar identidad, no basura")
        }
        let nan = FaceCropCalculator.exportTransform(
            sourceSize: CGSize(width: 1920, height: 1080), targetSize: target,
            center: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), mode: .autoFaceTrack)
        for v in [nan.a, nan.b, nan.c, nan.d, nan.tx, nan.ty] {
            XCTAssertTrue(v.isFinite, "NaN en transform ante centro inválido")
        }
    }

    // MARK: - Gemini vision mapper (sin red ni video)

    private func frame(_ id: String, _ scene: FrameScene, _ zone: SpeakerZone = .center, _ corner: PipCorner = .none, _ conf: Double = 0.9) -> FrameAnalysis {
        FrameAnalysis(id: id, scene: scene, speakerZone: zone, pipCorner: corner, confidence: conf)
    }

    func testMapperTalkingHeadPorTercios() {
        XCTAssertEqual(FrameFramingMapper.framing(for: frame("a", .talking_head, .left)).x, 0.25, accuracy: 0.001)
        XCTAssertEqual(FrameFramingMapper.framing(for: frame("b", .talking_head, .center)).x, 0.5, accuracy: 0.001)
        XCTAssertEqual(FrameFramingMapper.framing(for: frame("c", .talking_head, .right)).x, 0.75, accuracy: 0.001)
        // Sin zoom: el close-up ya llena el 9:16
        XCTAssertNil(FrameFramingMapper.framing(for: frame("d", .talking_head, .center)).faceWidth)
    }

    func testMapperFaceXMandaSobreTercio() {
        var f = frame("a", .talking_head, .center, .none, 0.9)
        f = FrameAnalysis(id: f.id, scene: f.scene, speakerZone: f.speakerZone, pipCorner: f.pipCorner, confidence: f.confidence, faceX: 70)
        XCTAssertEqual(FrameFramingMapper.framing(for: f).x, 0.7, accuracy: 0.001)
        // faceX inválido -> cae al tercio
        let g = FrameAnalysis(id: "g", scene: .talking_head, speakerZone: .left, pipCorner: .none, confidence: 0.9, faceX: -1)
        XCTAssertEqual(FrameFramingMapper.framing(for: g).x, 0.25, accuracy: 0.001)
    }

    func testMapperPipVaALaCara() {
        // PiP: la cara manda, no la pantalla. faceX=85 -> x 0.85, sin zoom fijo
        // (la ventana adaptativa la dimensiona el calculator con faceW).
        var f = frame("a", .pip, .right, .bottomRight, 0.9)
        f = FrameAnalysis(id: f.id, scene: f.scene, speakerZone: f.speakerZone, pipCorner: f.pipCorner, confidence: f.confidence, faceX: 85, faceY: 75, faceW: 10)
        let r = FrameFramingMapper.framing(for: f)
        XCTAssertEqual(r.mode, .autoFaceTrack)
        XCTAssertEqual(r.x, 0.85, accuracy: 0.001)
        XCTAssertEqual(r.y, 0.75, accuracy: 0.001)
        XCTAssertEqual(r.faceWidth ?? -1, 0.1, accuracy: 0.001)
    }

    func testMapperSiempreCaraNuncaPantalla() {
        // screen_share sin persona -> default neutro (centro), NO fondo: el crop
        // de cara no aplica pero tampoco se decapita a nadie.
        let s = FrameFramingMapper.framing(for: frame("a", .screen_share))
        XCTAssertEqual(s.mode, .autoFaceTrack)
        XCTAssertEqual(s.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(FrameFramingMapper.framing(for: frame("b", .unclear, .none, .none, 0.2)).mode, .autoFaceTrack)
        // Confianza baja aunque diga talking_head -> default seguro
        XCTAssertEqual(FrameFramingMapper.framing(for: frame("c", .talking_head, .left, .none, 0.2)).x, 0.5, accuracy: 0.001)
    }

    func testMapperBeatPromediaEnEmpate() {
        // Confianzas empatadas (dif < 0.15): promedia centros (suaviza ruido VLM)
        let bc = FrameFramingMapper.beatCenter(start: 10, end: 20, frames: [
            frame("t1", .talking_head, .left, .none, 0.85),
            frame("t2", .talking_head, .right, .none, 0.9),
        ])
        XCTAssertEqual(bc.x, 0.5, accuracy: 0.001)
    }

    func testMapperBeatCenterGanaMayorConfianza() {
        let bc = FrameFramingMapper.beatCenter(start: 10, end: 20, frames: [
            frame("t1", .talking_head, .left, .none, 0.6),
            frame("t2", .talking_head, .right, .none, 0.9),
        ])
        XCTAssertEqual(bc.x, 0.75, accuracy: 0.001)
        XCTAssertEqual(bc.start, 10, accuracy: 0.001)
        XCTAssertEqual(bc.end, 20, accuracy: 0.001)
    }

    func testMapperBeatSinConfianzaVaAlCentro() {
        let bc = FrameFramingMapper.beatCenter(start: 10, end: 20, frames: [
            frame("t1", .unclear, .none, .none, 0.1),
        ])
        XCTAssertEqual(bc.x, 0.5, accuracy: 0.001)
        XCTAssertNil(bc.faceWidth)
    }

    func testThumbTimesPorBeat() {
        XCTAssertEqual(FrameExtractorService.thumbTimes(forBeat: 10, end: 20).count, 2)
        XCTAssertEqual(FrameExtractorService.thumbTimes(forBeat: 10, end: 11).count, 1)
        XCTAssertTrue(FrameExtractorService.thumbTimes(forBeat: 20, end: 10).isEmpty)
    }


    func testBeatIndexParsing() {
        XCTAssertEqual(AppViewModel.beatIndex(of: "b2t0"), 2)
        XCTAssertEqual(AppViewModel.beatIndex(of: "b0t444.845"), 0)
        XCTAssertNil(AppViewModel.beatIndex(of: "xx"))
    }

    func testNormalizeSceneAnchorsLocksTalkingHead() {
        let raw = [
            BeatCenter(start: 0, end: 3, x: 0.48, y: 0.43, faceWidth: 0.22),
            BeatCenter(start: 3, end: 6, x: 0.52, y: 0.45, faceWidth: 0.20),
            BeatCenter(start: 6, end: 9, x: 0.50, y: 0.44, faceWidth: 0.24),
        ]
        let stabilized = AppViewModel.normalizeSceneAnchors(raw)
        XCTAssertEqual(stabilized.count, 3)
        // Todos deben tener la mediana fija (x: 0.50, y: 0.44, w: 0.22)
        for bc in stabilized {
            XCTAssertEqual(bc.x, 0.50, accuracy: 0.001)
            XCTAssertEqual(bc.y, 0.44, accuracy: 0.001)
            XCTAssertEqual(bc.faceWidth!, 0.22, accuracy: 0.001)
        }
    }

    func testNormalizeSceneAnchorsPreservesRealSceneCut() {
        let raw = [
            // Escena 1: webcam en esquina
            BeatCenter(start: 0, end: 3, x: 0.85, y: 0.80, faceWidth: 0.12),
            BeatCenter(start: 3, end: 6, x: 0.83, y: 0.82, faceWidth: 0.14),
            // Escena 2: corte a talking head centrado
            BeatCenter(start: 6, end: 9, x: 0.50, y: 0.45, faceWidth: 0.25),
            BeatCenter(start: 9, end: 12, x: 0.48, y: 0.43, faceWidth: 0.23),
        ]
        let stabilized = AppViewModel.normalizeSceneAnchors(raw)
        XCTAssertEqual(stabilized.count, 4)
        // Escena 1 estabilizada
        XCTAssertEqual(stabilized[0].x, 0.85, accuracy: 0.02)
        XCTAssertEqual(stabilized[1].x, 0.85, accuracy: 0.02)
        // Escena 2 estabilizada
        XCTAssertEqual(stabilized[2].x, 0.50, accuracy: 0.02)
        XCTAssertEqual(stabilized[3].x, 0.50, accuracy: 0.02)
    }

    // MARK: - orientedSize (rotación iPhone)

    func testOrientedSizeTraspone90() {
        // iPhone landscape: píxeles 1080x1920 + rotación 90° => display 1920x1080
        let rot = CGAffineTransform(rotationAngle: .pi / 2)
        let s = FaceCropCalculator.orientedSize(
            naturalSize: CGSize(width: 1080, height: 1920), preferredTransform: rot)
        XCTAssertEqual(s.width, 1920, accuracy: 0.001)
        XCTAssertEqual(s.height, 1080, accuracy: 0.001)
    }

    func testOrientedSizeIdentidadNoToca() {
        let s = FaceCropCalculator.orientedSize(
            naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: .identity)
        XCTAssertEqual(s.width, 1920, accuracy: 0.001)
        XCTAssertEqual(s.height, 1080, accuracy: 0.001)
    }

    // MARK: - FaceTrackService (curva continua)

    private func raw(_ t: Double, _ x: Double, _ y: Double, _ w: Double = 0.2) -> (t: Double, rect: CGRect?, conf: Double) {
        (t, CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w), 0.9)
    }

    func testSmoothSigueDerivaSinSaltos() {
        // Cara a la deriva lenta 0.3 -> 0.5: la curva la sigue, sin cortes.
        let raws = [raw(0, 0.3, 0.4), raw(1, 0.4, 0.4), raw(2, 0.5, 0.4)]
        let track = FaceTrackService.smooth(raws: raws, range: (0, 2))
        XCTAssertTrue(track.hardCuts.isEmpty)
        XCTAssertEqual(track.samples.count, 3)
        XCTAssertLessThan(track.samples[1].x, 0.5)
        XCTAssertGreaterThan(track.samples[2].x, track.samples[0].x)
    }

    func testSmoothCorteDuroEnSalto() {
        // Salto 0.3 -> 0.9: otra toma, corte duro y reanclaje.
        let raws = [raw(0, 0.3, 0.4), raw(1, 0.9, 0.4)]
        let track = FaceTrackService.smooth(raws: raws, range: (0, 1))
        XCTAssertEqual(track.hardCuts, [1])
        XCTAssertEqual(track.samples[1].x, 0.9, accuracy: 0.001)
    }

    func testSmoothSinCaraMantiene() {
        // Gap sin cara: mantiene última posición con conf 0.
        let raws = [raw(0, 0.4, 0.4), (t: 1.0, rect: nil as CGRect?, conf: 0.0)]
        let track = FaceTrackService.smooth(raws: raws, range: (0, 1))
        XCTAssertEqual(track.samples[1].x, track.samples[0].x, accuracy: 0.001)
        XCTAssertEqual(track.samples[1].conf, 0, accuracy: 0.001)
    }

    func testCenterInterpola() {
        let track = FaceTrackService.Track(samples: [
            FaceTrackService.Sample(t: 0, x: 0.3, y: 0.4, w: 0.2, conf: 1),
            FaceTrackService.Sample(t: 2, x: 0.5, y: 0.4, w: 0.2, conf: 1),
        ], hardCuts: [])
        let c = FaceTrackService.center(at: 1, in: track)
        XCTAssertEqual(c.x, 0.4, accuracy: 0.001)
    }
}
