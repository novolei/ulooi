import Foundation
import AVFoundation
import AudioToolbox

/// A zero-dependency, real-time audio synthesizer utilizing Apple's native `AVAudioEngine`
/// and `AVAudioSourceNode`. It programmatically generates futuristic sound effects (scifi sweeps,
/// mechanical locks, and playful startup chirps) with zero file weight, and integrates
/// iOS system sound fallbacks for bulletproof execution.
public final class SciFiAudioSynth: @unchecked Sendable {
    
    public static let shared = SciFiAudioSynth()
    
    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    
    // Thread safety lock for synthesis parameters
    private let queue = DispatchQueue(label: "ulooi.audiosynth.queue", qos: .userInteractive)
    
    // --- Synthesis States ---
    private var phase: Float = 0.0
    private var sampleRate: Double = 44100.0
    private var frequency: Float = 440.0
    private var targetFrequency: Float = 440.0
    private var frequencyGlideRate: Float = 0.0
    private var amplitude: Float = 0.0
    private var amplitudeDecay: Float = 0.0
    private var waveType: WaveType = .sine
    
    private enum WaveType {
        case sine
        case square
        case triangle
    }
    
    private init() {
        setupAudioEngine()
    }
    
    /// Prepares and starts the native AVAudioEngine
    private func setupAudioEngine() {
        let inputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        self.sampleRate = inputFormat.sampleRate
        
        // Construct the custom source node that synthesizes PCM buffers on the fly
        let node = AVAudioSourceNode { [weak self] (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
            guard let self = self else { return noErr }
            
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = buffers.first, let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            
            let status = self.queue.sync { () -> OSStatus in
                if self.amplitude <= 0.001 {
                    isSilence.pointee = true
                    // Fill buffer with silence
                    for frame in 0..<Int(frameCount) {
                        ptr[frame] = 0.0
                    }
                    return noErr
                }
                
                isSilence.pointee = false
                
                for frame in 0..<Int(frameCount) {
                    // Glide frequency
                    if abs(self.frequency - self.targetFrequency) > 0.1 {
                        self.frequency += (self.targetFrequency - self.frequency) * self.frequencyGlideRate
                    }
                    
                    // Generate wave sample
                    var sample: Float = 0.0
                    let phaseStep = 2.0 * .pi * self.frequency / Float(self.sampleRate)
                    
                    switch self.waveType {
                    case .sine:
                        sample = sin(self.phase)
                    case .square:
                        sample = sin(self.phase) >= 0 ? 1.0 : -1.0
                    case .triangle:
                        sample = abs((self.phase / .pi).truncatingRemainder(dividingBy: 2.0) - 1.0) * 2.0 - 1.0
                    }
                    
                    // Apply envelope amplitude
                    ptr[frame] = sample * self.amplitude
                    
                    // Decay amplitude
                    self.amplitude *= self.amplitudeDecay
                    
                    // Advance phase
                    self.phase = (self.phase + phaseStep).truncatingRemainder(dividingBy: 2.0 * .pi)
                }
                return noErr
            }
            
            return status
        }
        
        self.sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: inputFormat)
        
        do {
            try audioEngine.start()
        } catch {
            print("⚠️ AVAudioEngine starting failed: \(error.localizedDescription)")
        }
    }
    
    // --- Sci-Fi Playback APIs ---
    
    /// A periodic sonar-like search ping for BLE scanning
    public func playRadarPing() {
        // Fallback: 1104 is a keyboard tap sound
        AudioServicesPlaySystemSound(1104) 
        
        queue.async {
            self.phase = 0.0
            self.waveType = .sine
            self.frequency = 600.0
            self.targetFrequency = 300.0
            self.frequencyGlideRate = 0.005 // Slide down
            self.amplitude = 0.4
            self.amplitudeDecay = 0.99988 // Slow decay
        }
    }
    
    /// A sharp, crisp dual-tone lock snap representing connection
    public func playLockSnap() {
        // Fallback: 1020 is a premium Lock tick sound
        AudioServicesPlaySystemSound(1020)
        
        queue.async {
            self.phase = 0.0
            self.waveType = .square
            self.frequency = 900.0
            self.targetFrequency = 900.0
            self.frequencyGlideRate = 0.0
            self.amplitude = 0.3
            self.amplitudeDecay = 0.9985 // Fast snap decay
        }
    }
    
    /// Programmatically synthesizes the Pentatonic scale notes on each progressive handshake step.
    /// Provides beautiful metallic chime audio cues mapped directly to pairing progress.
    public func playNeuralSyncPitch(step: Int, totalSteps: Int) {
        let scale: [Float] = [
            261.63, // C4
            293.66, // D4
            329.63, // E4
            392.00, // G4
            440.00, // A4
            523.25, // C5
            587.33, // D5
            659.25, // E5
            783.99, // G5
            880.00, // A5
            1046.50 // C6
        ]
        
        let index: Int
        if totalSteps <= 1 {
            index = max(0, min(step, scale.count - 1))
        } else {
            let ratio = Double(step) / Double(totalSteps)
            index = max(0, min(Int(ratio * Double(scale.count)), scale.count - 1))
        }
        let note = scale[index]
        
        // System sound click fallback for sensory assurance
        AudioServicesPlaySystemSound(1104)
        
        queue.async {
            self.phase = 0.0
            self.waveType = .sine
            self.frequency = note
            self.targetFrequency = note * 1.03 // Subtle upward slide
            self.frequencyGlideRate = 0.006
            self.amplitude = 0.35
            self.amplitudeDecay = 0.9994 // Moderately slow decay for beautiful chime ring
        }
    }
    
    /// A cheerful pentatonic rising synth sweep representing Looi waking up (Climax)
    public func playStartupChirp() {
        // Fallback: 1407 represents a satisfying spatial pairing completed sound
        AudioServicesPlaySystemSound(1407)
        
        // Trigger high-frequency programmatic arpeggio run
        Task {
            let notes: [Float] = [523.25, 659.25, 783.99, 880.00, 1046.50, 1318.51, 1567.98] // C5 -> E5 -> G5 -> A5 -> C6 -> E6 -> G6
            for (index, note) in notes.enumerated() {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = index % 2 == 0 ? .sine : .triangle
                    self.frequency = note
                    self.targetFrequency = note * 1.08 // Quick slide up
                    self.frequencyGlideRate = 0.018
                    self.amplitude = 0.40 - (Float(index) * 0.02)
                    self.amplitudeDecay = index == notes.count - 1 ? 0.9997 : 0.9991
                }
                try? await Task.sleep(for: .milliseconds(75))
            }
            
            // Final resonant high chime
            try? await Task.sleep(for: .milliseconds(150))
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 1046.50 // C6
                self.targetFrequency = 2093.00 // C7 slide
                self.frequencyGlideRate = 0.003
                self.amplitude = 0.45
                self.amplitudeDecay = 0.99985 // Slower decay for beautiful chime ring out
            }
        }
    }
    
    // --- WALL-E Robotic Vocal Synthesis APIs ---
    
    /// Bubbly, rapid rising/falling triangle wave sweeps mimicking WALL-E's excited chatter
    public func playWallEChirp() {
        AudioServicesPlaySystemSound(1104) // soft click fallback
        
        Task {
            // Rapid double chirp sweeps
            let sweep1: [Float] = [600.0, 750.0, 900.0, 1050.0, 1200.0]
            for (index, freq) in sweep1.enumerated() {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .triangle
                    self.frequency = freq
                    self.targetFrequency = freq * 1.15
                    self.frequencyGlideRate = 0.03
                    self.amplitude = 0.38 - (Float(index) * 0.03)
                    self.amplitudeDecay = 0.9985
                }
                try? await Task.sleep(for: .milliseconds(35))
            }
            
            try? await Task.sleep(for: .milliseconds(45))
            
            let sweep2: [Float] = [800.0, 950.0, 1100.0, 1250.0, 1400.0]
            for (index, freq) in sweep2.enumerated() {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .triangle
                    self.frequency = freq
                    self.targetFrequency = freq * 1.18
                    self.frequencyGlideRate = 0.035
                    self.amplitude = 0.42 - (Float(index) * 0.02)
                    self.amplitudeDecay = index == sweep2.count - 1 ? 0.9992 : 0.9982
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
    
    /// The classic, inquisitive, warm robotic questioning vocal sweep ("Oooh-hu?")
    public func playWallECuriosity() {
        AudioServicesPlaySystemSound(1104)
        
        Task {
            // "Ooo" - starts mid-pitch, drops slightly, and then "hu?" leaps up
            // We simulate this as a continuous sliding wave with low-frequency vibrato
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 420.0
                self.targetFrequency = 340.0 // dip down
                self.frequencyGlideRate = 0.015
                self.amplitude = 0.38
                self.amplitudeDecay = 0.9998 // very slow decay to keep vocal active
            }
            
            try? await Task.sleep(for: .milliseconds(140))
            
            // Rapid leap upward for the question "hu?"
            self.queue.async {
                self.waveType = .triangle
                self.targetFrequency = 580.0 // sweep up high
                self.frequencyGlideRate = 0.025
                self.amplitude = 0.44
                self.amplitudeDecay = 0.9994 // gentle ring out
            }
            
            // Introduce a subtle frequency vibration (FM-like tremolo) to make it vocal
            for i in 0..<8 {
                try? await Task.sleep(for: .milliseconds(30))
                self.queue.async {
                    // alternate frequency slightly
                    let mod = sin(Float(i) * 1.2) * 15.0
                    self.frequency += mod
                }
            }
        }
    }
    
    /// Descending, decaying metallic "Aww..." vocal expressing disappointment or sadness
    public func playWallESad() {
        AudioServicesPlaySystemSound(1020)
        
        Task {
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 320.0
                self.targetFrequency = 180.0 // slide down far
                self.frequencyGlideRate = 0.006 // slow slide
                self.amplitude = 0.42
                self.amplitudeDecay = 0.99975 // long slow decay
            }
            
            // Add a shaking metallic vibrato
            for i in 0..<12 {
                try? await Task.sleep(for: .milliseconds(40))
                self.queue.async {
                    let mod = sin(Float(i) * 1.8) * 10.0
                    self.frequency += mod
                    // dim volume slightly
                    self.amplitude *= 0.95
                }
            }
        }
    }
    
    /// Yawning, sleepy, fading low frequency sine sweeps ending in deep silence
    public func playWallESleepy() {
        Task {
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 380.0
                self.targetFrequency = 150.0 // yawn down
                self.frequencyGlideRate = 0.005
                self.amplitude = 0.35
                self.amplitudeDecay = 0.99984 // long yawn
            }
            
            // Slower amplitude fade-out
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(80))
                self.queue.async {
                    self.amplitude *= 0.88
                }
            }
            
            self.stop()
        }
    }
    
    /// High-frequency alert/alarm pulse representing sudden surprise or warning
    public func playWallEAlarm() {
        AudioServicesPlaySystemSound(1020)
        
        Task {
            // Rapid double alert chirp
            for _ in 0..<3 {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .square // square wave for sharp mechanical sound
                    self.frequency = 880.0
                    self.targetFrequency = 1200.0
                    self.frequencyGlideRate = 0.04
                    self.amplitude = 0.35
                    self.amplitudeDecay = 0.9982
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
    
    /// Joyful, shimmering high-frequency burst for celebration🎉
    public func playCelebrationChirp() {
        AudioServicesPlaySystemSound(1104)
        Task {
            // Rapid high-pitched chime run with alternating frequencies
            let notes: [Float] = [659.25, 783.99, 880.00, 1046.50, 1318.51, 1567.98]
            for (index, note) in notes.enumerated() {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .triangle
                    self.frequency = note
                    self.targetFrequency = note * 1.2
                    self.frequencyGlideRate = 0.04
                    self.amplitude = 0.45 - (Float(index) * 0.03)
                    self.amplitudeDecay = 0.9992
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            // Sparkle bursts
            for _ in 0..<3 {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .sine
                    self.frequency = 1500.0 + Float.random(in: -200...200)
                    self.targetFrequency = 2000.0
                    self.frequencyGlideRate = 0.05
                    self.amplitude = 0.35
                    self.amplitudeDecay = 0.9980
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Prideful rising pentatonic march/fanfare representing victory🏆
    public func playVictoryFanfare() {
        AudioServicesPlaySystemSound(1407)
        Task {
            // Majestic rising dual-tones
            let chords: [Float] = [523.25, 659.25, 783.99, 1046.50, 1318.51]
            for note in chords {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .sine
                    self.frequency = note
                    self.targetFrequency = note
                    self.frequencyGlideRate = 0.0
                    self.amplitude = 0.45
                    self.amplitudeDecay = 0.9996 // slow decay for resonance
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            // Sustained victorious chord
            self.queue.async {
                self.phase = 0.0
                self.waveType = .triangle
                self.frequency = 1046.50
                self.targetFrequency = 1046.50
                self.frequencyGlideRate = 0.0
                self.amplitude = 0.5
                self.amplitudeDecay = 0.9998
            }
        }
    }

    /// Playful gurgling, bubbling synth mimicking fluid being poured or drank🍷
    public func playDrinkingBubbles() {
        AudioServicesPlaySystemSound(1104)
        Task {
            // Rapid random bubbly pops with sine waves
            for i in 0..<12 {
                let note = 400.0 + Float(i) * 35.0 + Float.random(in: -50...50)
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .sine
                    self.frequency = note
                    self.targetFrequency = note + 120.0
                    self.frequencyGlideRate = 0.06
                    self.amplitude = 0.38
                    self.amplitudeDecay = 0.9975 // fast decay for "pop" effect
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Smooth, gliding swoosh representing cool sunglasses/swag😎
    public func playCoolSwoosh() {
        AudioServicesPlaySystemSound(1020)
        Task {
            // Slow, deep swooshing sweep from high to low and back up
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 600.0
                self.targetFrequency = 300.0
                self.frequencyGlideRate = 0.008
                self.amplitude = 0.4
                self.amplitudeDecay = 0.9998
            }
            try? await Task.sleep(for: .milliseconds(180))
            self.queue.async {
                self.targetFrequency = 700.0
                self.frequencyGlideRate = 0.012
                self.amplitude = 0.45
            }
        }
    }

    /// Adorable high-pitched soft chirping for acting cute (Aegyo/喵呜)❤️
    public func playCuteChirp() {
        AudioServicesPlaySystemSound(1104)
        Task {
            // Sweet rising double chirp
            for _ in 0..<2 {
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .sine
                    self.frequency = 880.0
                    self.targetFrequency = 1200.0
                    self.frequencyGlideRate = 0.035
                    self.amplitude = 0.35
                    self.amplitudeDecay = 0.9985
                }
                try? await Task.sleep(for: .milliseconds(70))
                self.queue.async {
                    self.phase = 0.0
                    self.waveType = .sine
                    self.frequency = 1046.50
                    self.targetFrequency = 1450.0
                    self.frequencyGlideRate = 0.04
                    self.amplitude = 0.38
                    self.amplitudeDecay = 0.9982
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// Trembling, shivering, fast vibrating tone representing fear/terror😨
    public func playFearTremolo() {
        AudioServicesPlaySystemSound(1020)
        Task {
            self.queue.async {
                self.phase = 0.0
                self.waveType = .square // harsh square
                self.frequency = 480.0
                self.targetFrequency = 450.0
                self.frequencyGlideRate = 0.02
                self.amplitude = 0.38
                self.amplitudeDecay = 0.9997
            }
            // Tremolo frequency modulation
            for i in 0..<20 {
                try? await Task.sleep(for: .milliseconds(25))
                self.queue.async {
                    // alternate frequency back and forth rapidly
                    let mod: Float = (i % 2 == 0) ? 60.0 : -60.0
                    self.frequency = 460.0 + mod
                    self.amplitude *= 0.97
                }
            }
        }
    }

    /// Descending, heavy, soft-volume mechanical sigh representing ashamed/ashamed😓
    public func playAshamedSigh() {
        AudioServicesPlaySystemSound(1020)
        Task {
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 350.0
                self.targetFrequency = 120.0 // drop very low
                self.frequencyGlideRate = 0.004
                self.amplitude = 0.32
                self.amplitudeDecay = 0.9998
            }
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(90))
                self.queue.async {
                    self.amplitude *= 0.85
                }
            }
        }
    }

    /// Shy, quiet, hesitant chirp sliding up slightly and fading quickly
    public func playShyChirp() {
        AudioServicesPlaySystemSound(1104)
        Task {
            self.queue.async {
                self.phase = 0.0
                self.waveType = .sine
                self.frequency = 580.0
                self.targetFrequency = 680.0
                self.frequencyGlideRate = 0.008
                self.amplitude = 0.28 // softer volume
                self.amplitudeDecay = 0.9993
            }
            try? await Task.sleep(for: .milliseconds(120))
            self.queue.async {
                self.amplitudeDecay = 0.9982 // fade quickly
            }
        }
    }
    
    /// Instantly silences the synth
    public func stop() {
        queue.async {
            self.amplitude = 0.0
        }
    }
}
