import Foundation
import Accelerate
import CoreVideo

/// Detects active emergency lights (flashing red/blue at ~1–10 Hz).
///
/// **No ML model needed.** Pure signal processing:
///   1. For each tracked vehicle, sample the upper-body region's mean red +
///      blue + luma each frame (fast CIAreaAverage single-pixel reduction).
///   2. Accumulate samples in a ring buffer (2–4 s).
///   3. Run FFT (Accelerate) per channel.
///   4. Look for a dominant peak in the 1–10 Hz band.
///   5. Bicolor bonus: if red AND blue both peak in that band, very strong signal.
///
/// Works day and night (lights modulate at the same frequency even when the
/// contrast shifts with ambient light).
final class EmergencyLightDetector: @unchecked Sendable {
    /// Expected emergency-light flash frequency range.
    private let minFrequencyHz: Float = 1.0
    private let maxFrequencyHz: Float = 10.0

    /// Extract one frame's color sample for a vehicle. Call this every frame
    /// the detector processes so the ring buffer stays current.
    func sample(
        pixelBuffer: CVPixelBuffer,
        vehicleBox: CGRect,
        imageSize: CGSize,
        timestamp: TimeInterval
    ) -> ColorSample? {
        guard let crop = PixelBufferUtilities.upperBodyCrop(
            from: pixelBuffer,
            vehicleBox: vehicleBox,
            imageSize: imageSize
        ) else { return nil }

        guard let channels = PixelBufferUtilities.meanChannels(of: crop) else {
            return nil
        }
        return ColorSample(
            timestamp: timestamp,
            redMean: channels.red,
            blueMean: channels.blue,
            whiteMean: channels.luma
        )
    }

    /// Analyze a track's accumulated samples → emergency-light score.
    func analyze(track: VehicleTrack) -> EmergencyLightSignal {
        let samples = track.colorSamples.values
        guard samples.count >= 30 else {
            return EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false)
        }

        // Resample uniformly using the median inter-sample interval.
        let dts = zip(samples.dropFirst(), samples).map { Float($0.timestamp - $1.timestamp) }
        let sorted = dts.sorted()
        guard dts.count > 0 else {
            return EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false)
        }
        let medianDt = sorted[sorted.count / 2]
        guard medianDt > 0 else {
            return EmergencyLightSignal(score: 0, frequencyHz: 0, bicolor: false)
        }
        let sampleRate = 1.0 / medianDt

        let red = samples.map(\.redMean)
        let blue = samples.map(\.blueMean)

        let redPeak = dominantPeak(signal: red, sampleRate: sampleRate)
        let bluePeak = dominantPeak(signal: blue, sampleRate: sampleRate)

        let redInBand = (minFrequencyHz...maxFrequencyHz).contains(redPeak.frequency)
        let blueInBand = (minFrequencyHz...maxFrequencyHz).contains(bluePeak.frequency)
        let frequencyAgreement = abs(redPeak.frequency - bluePeak.frequency) < 1.0

        var score: Float = 0
        if redInBand { score += 0.35 * redPeak.strength }
        if blueInBand { score += 0.35 * bluePeak.strength }
        let bicolor = redInBand && blueInBand && frequencyAgreement
        if bicolor { score += 0.30 }
        score = min(1.0, score)

        let domFreq = bicolor
            ? (redPeak.frequency + bluePeak.frequency) / 2
            : (redPeak.strength > bluePeak.strength ? redPeak.frequency : bluePeak.frequency)

        return EmergencyLightSignal(score: score, frequencyHz: domFreq, bicolor: bicolor)
    }

    // MARK: - FFT

    private struct Peak {
        let frequency: Float
        /// Normalized peak strength, 0…1.
        let strength: Float
    }

    /// Compute the dominant frequency peak of a 1-D signal via Accelerate FFT.
    private func dominantPeak(signal input: [Float], sampleRate: Float) -> Peak {
        guard input.count >= 16 else { return Peak(frequency: 0, strength: 0) }

        let n = nextPowerOfTwo(input.count)
        var padded = input + [Float](repeating: 0, count: n - input.count)

        // Remove DC bias.
        let mean = padded.reduce(0, +) / Float(padded.count)
        for i in 0..<padded.count { padded[i] -= mean }

        // Hann window to limit spectral leakage.
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(padded, 1, window, 1, &padded, 1, vDSP_Length(n))

        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Peak(frequency: 0, strength: 0)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                            imagp: imagPtr.baseAddress!)
                padded.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        var magnitudes = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        // Skip DC (bin 0) and the very-low-frequency noise bin.
        let startBin = 2
        guard magnitudes.count > startBin else { return Peak(frequency: 0, strength: 0) }

        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        magnitudes.withUnsafeBufferPointer { ptr in
            let offsetPtr = ptr.baseAddress!.advanced(by: startBin)
            vDSP_maxvi(offsetPtr, 1, &maxVal, &maxIdx,
                       vDSP_Length(magnitudes.count - startBin))
        }
        let peakBin = Int(maxIdx) + startBin
        let binWidthHz = sampleRate / Float(n)
        let peakFreq = Float(peakBin) * binWidthHz

        let totalEnergy = magnitudes.reduce(0, +)
        let strength: Float = totalEnergy > 0
            ? min(1.0, maxVal / (totalEnergy / Float(magnitudes.count - startBin))) / 10.0
            : 0

        return Peak(frequency: peakFreq, strength: min(1.0, strength))
    }

    private func nextPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
