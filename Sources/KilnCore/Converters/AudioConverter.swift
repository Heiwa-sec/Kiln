import AVFoundation

struct AudioConverter: Converter {
    static let inputs: [Format] = [.mp3, .m4a, .wav, .aiff, .flac, .caf]
    static let outputs: [Format] = [.m4a, .wav, .aiff, .caf, .flac]
    let pairs = inputs.flatMap { i in outputs.filter { $0 != i }.map { ConversionKey(i, $0) } }

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let src: AVAudioFile
        do { src = try AVAudioFile(forReading: input) } catch { throw KilnError.corruptInput(input.lastPathComponent) }
        let fmt = src.processingFormat
        let ch = Int(fmt.channelCount)
        var settings: [String: Any] = [AVSampleRateKey: fmt.sampleRate, AVNumberOfChannelsKey: ch]
        switch key.output {
        case .m4a: settings[AVFormatIDKey] = kAudioFormatMPEG4AAC; settings[AVEncoderBitRateKey] = output.options.aacKbpsPerChannel * 1000 * ch
        case .flac: settings[AVFormatIDKey] = kAudioFormatFLAC
        default:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM; settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false; settings[AVLinearPCMIsBigEndianKey] = key.output == .aiff
        }
        let out = try output.url(ext: key.output.ext)
        let dst = try AVAudioFile(forWriting: out, settings: settings, commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16_384) else { throw KilnError.io("no audio buffer") }
        while src.framePosition < src.length {
            try Task.checkCancellation()
            try src.read(into: buf)
            if buf.frameLength == 0 { break }
            try dst.write(from: buf)
            progress(Double(src.framePosition) / Double(max(src.length, 1)))
        }
    }
}
