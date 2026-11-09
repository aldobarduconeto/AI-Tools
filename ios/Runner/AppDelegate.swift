import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
    UIDocumentPickerDelegate {
  private var mediaExport: (directory: URL, result: FlutterResult)?
  private var narrator: AVSpeechSynthesizer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AiToolsMedia")
    else { return }
    FlutterMethodChannel(name: "ai_tools/media", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { [weak self] call, result in
        self?.handleMedia(call, result: result)
      }
  }

  private func handleMedia(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "decodeAudio" {
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "audio", message: "Selecione um arquivo de áudio.", details: nil))
        return
      }
      convertAudio(URL(fileURLWithPath: path), result: result)
      return
    }
    if call.method == "speech" {
      guard let text = call.arguments as? String, !text.isEmpty, narrator == nil else {
        result(FlutterError(code: "speech", message: "Informe o texto da narração.", details: nil))
        return
      }
      narrate(text, result: result)
      return
    }
    guard ["export", "clip", "posterVideo"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard mediaExport == nil else {
      result(FlutterError(code: "busy", message: "Uma exportação já está em andamento.", details: nil))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      mediaExport = (directory, result)
      if call.method == "posterVideo" {
        guard let png = arguments["png"] as? FlutterStandardTypedData,
              let image = UIImage(data: png.data)?.cgImage,
              let seconds = arguments["seconds"] as? Double,
              seconds.isFinite, seconds >= 1.0 / 15, seconds < Double(Int64.max) / 60000 else {
          finishMedia(message: "Informe uma imagem e uma duração válidas.")
          return
        }
        try renderPoster(image, seconds: seconds, to: directory.appendingPathComponent("cartaz.mp4"))
      } else if call.method == "clip" {
        guard let path = arguments["path"] as? String else {
          finishMedia(message: "Selecione o vídeo novamente.")
          return
        }
        let destination = directory.appendingPathComponent("video.mp4")
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              exporter.supportedFileTypes.contains(.mp4) else {
          finishMedia(message: "Não foi possível exportar este vídeo em MP4.")
          return
        }
        exporter.outputURL = destination
        exporter.outputFileType = .mp4
        if let end = arguments["end"] as? Double, end.isFinite, end > 0 {
          let requested = CMTime(seconds: end, preferredTimescale: 60000)
          let duration = CMTimeMinimum(requested, asset.duration)
          exporter.timeRange = CMTimeRange(start: .zero, duration: duration)
        }
        exporter.exportAsynchronously { [weak self] in
          DispatchQueue.main.async {
            if exporter.status == .completed {
              self?.presentMedia(destination)
            } else {
              self?.finishMedia(message: exporter.error?.localizedDescription ?? "Falha ao exportar o vídeo.")
            }
          }
        }
      } else {
        guard let data = arguments["bytes"] as? FlutterStandardTypedData,
              let name = arguments["name"] as? String,
              (name as NSString).lastPathComponent == name,
              ["png", "jpg", "mp3"].contains((name as NSString).pathExtension.lowercased()) else {
          finishMedia(message: "Selecione um arquivo PNG, JPG ou MP3.")
          return
        }
        let destination = directory.appendingPathComponent(name)
        try data.data.write(to: destination)
        presentMedia(destination)
      }
    } catch {
      if mediaExport == nil {
        result(FlutterError(code: "export", message: error.localizedDescription, details: nil))
      } else {
        finishMedia(message: error.localizedDescription)
      }
    }
  }

  private func convertAudio(_ input: URL, removeInput: Bool = false, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      defer { if removeInput { try? FileManager.default.removeItem(at: input) } }
      do {
        let wav = try Self.pcmWav(input)
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: wav)) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func pcmWav(_ url: URL) throws -> Data {
    let source = try AVAudioFile(forReading: url)
    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
              sampleRate: 16000, channels: 1, interleaved: true),
          let converter = AVAudioConverter(from: source.processingFormat, to: format),
          let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096),
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
      throw NSError(domain: "AI Tools", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Formato de áudio incompatível."])
    }
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    defer { try? FileManager.default.removeItem(at: destination) }
    do {
      let wav = try AVAudioFile(forWriting: destination, settings: format.settings,
        commonFormat: .pcmFormatInt16, interleaved: true)
      var readError: Error?
      var done = false
      while !done {
        var error: NSError?
        output.frameLength = 0
        let status = converter.convert(to: output, error: &error) { requested, state in
          do {
            try source.read(into: input, frameCount: min(requested, input.frameCapacity))
            state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
            return input.frameLength == 0 ? nil : input
          } catch {
            readError = error
            state.pointee = .endOfStream
            return nil
          }
        }
        if let readError = readError { throw readError }
        if let error = error { throw error }
        if status == .error {
          throw NSError(domain: "AI Tools", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Falha ao decodificar o áudio."])
        }
        if output.frameLength > 0 { try wav.write(from: output) }
        done = status == .endOfStream
      }
    }
    return try Data(contentsOf: destination)
  }

  private func narrate(_ text: String, result: @escaping FlutterResult) {
    let synth = AVSpeechSynthesizer()
    narrator = synth
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
    var file: AVAudioFile?
    synth.write(utterance) { [weak self] buffer in
      DispatchQueue.main.async {
        guard let self = self, self.narrator === synth,
              let pcm = buffer as? AVAudioPCMBuffer else { return }
        do {
          if pcm.frameLength == 0 {
            file = nil
            self.narrator = nil
            self.convertAudio(destination, removeInput: true, result: result)
          } else {
            if file == nil {
              file = try AVAudioFile(forWriting: destination, settings: pcm.format.settings,
                commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
          }
        } catch {
          file = nil
          self.narrator = nil
          synth.stopSpeaking(at: .immediate)
          try? FileManager.default.removeItem(at: destination)
          result(FlutterError(code: "speech", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func renderPoster(_ image: CGImage, seconds: Double, to url: URL) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: image.width,
      AVVideoHeightKey: image.height
    ])
    let frames = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: image.width,
        kCVPixelBufferHeightKey as String: image.height
      ])
    guard writer.canAdd(input) else {
      finishMedia(message: "O codificador de vídeo está indisponível.")
      return
    }
    writer.add(input)
    guard writer.startWriting() else {
      finishMedia(message: writer.error?.localizedDescription ?? "Falha ao iniciar o vídeo.")
      return
    }
    writer.startSession(atSourceTime: .zero)
    var pixelBuffer: CVPixelBuffer?
    guard let pool = frames.pixelBufferPool,
          CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
          let pixels = pixelBuffer else {
      writer.cancelWriting()
      finishMedia(message: "Não foi possível preparar o quadro do vídeo.")
      return
    }
    CVPixelBufferLockBaseAddress(pixels, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels),
      width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    context?.draw(image, in: CGRect(
      x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)
    ))
    CVPixelBufferUnlockBaseAddress(pixels, [])
    guard context != nil else {
      writer.cancelWriting()
      finishMedia(message: "Não foi possível desenhar o quadro do vídeo.")
      return
    }
    let count = Int64(ceil(seconds * 15))
    var frame: Int64 = 0
    var finishing = false
    input.requestMediaDataWhenReady(on: DispatchQueue(label: "ai-tools.poster")) { [weak self] in
      guard !finishing else { return }
      while input.isReadyForMoreMediaData && frame < count {
        if !frames.append(pixels, withPresentationTime: CMTime(value: frame, timescale: 15)) {
          finishing = true
          writer.cancelWriting()
          DispatchQueue.main.async { self?.finishMedia(message: "Falha ao codificar o vídeo.") }
          return
        }
        frame += 1
      }
      if frame == count {
        finishing = true
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 60000))
        input.markAsFinished()
        writer.finishWriting {
          DispatchQueue.main.async {
            if writer.status == .completed {
              self?.presentMedia(url)
            } else {
              self?.finishMedia(message: writer.error?.localizedDescription ?? "Falha ao salvar o vídeo.")
            }
          }
        }
      }
    }
  }

  private func presentMedia(_ url: URL) {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    guard var presenter = window?.rootViewController else {
      finishMedia(message: "Não foi possível abrir o seletor de arquivos.")
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishMedia(saved: !urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishMedia()
  }

  private func finishMedia(saved: Bool = false, message: String? = nil) {
    guard let export = mediaExport else { return }
    mediaExport = nil
    try? FileManager.default.removeItem(at: export.directory)
    if let message = message {
      export.result(FlutterError(code: "export", message: message, details: nil))
    } else {
      export.result(saved)
    }
  }
}
