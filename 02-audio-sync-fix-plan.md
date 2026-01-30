# Audio Sync Fix Plan

## Overview

This document outlines the strategy to fix two issues in the Vid player:

1. **Audio not playing on next/previous** - When navigating videos using playback buttons, audio sometimes doesn't play
2. **Video ahead of audio** - Video appears ~20-50ms ahead of audio in some cases

---

## Root Cause Analysis

### Issue 1: Audio Not Playing on Next/Previous

After analyzing [PlayerViewModel.swift](Vid/ViewModels/PlayerViewModel.swift), specifically `playNext()` (lines 389-403), `playPrevious()` (lines 405-424), and `startPlayback()` (lines 210-270):

| Cause | Location | Description |
|-------|----------|-------------|
| Silent failure | Lines 239-247 | `audioFile` loading errors are printed but not handled |
| Race condition | Lines 249-256 | `playerItem.status` publisher may fire before audio is ready |
| Incomplete reset | Lines 217-218 | `playerNode.stop()` alone doesn't clear scheduled buffers |
| No validation | Line 273 | `prerollAndStartSynchronized` doesn't verify audio is ready |

### Issue 2: Video Ahead of Audio

From `prerollAndStartSynchronized()` (lines 273-354) and `resyncAudio()` (lines 484-526):

| Cause | Location | Description |
|-------|----------|-------------|
| Output latency ignored | Lines 324-341 | AVAudioEngine has ~20-50ms output latency not compensated |
| Immediate play on resync | Lines 520-524 | `playerNode.play()` called without host time alignment |
| No audio prebuffering | Line 314 | Video gets `preroll()` but audio has no equivalent step |
| Loose threshold | Line 38 | 40ms threshold may allow perceptible drift |

---

## Phase 1: Fix Audio Not Playing

### 1.1 Add Audio File Loading Validation

**Location:** `startPlayback()` lines 239-257

**Problem:** Audio file loading can fail silently, and playback continues anyway.

**Solution:**
```swift
/// Prepares audio file for playback, returns success status
private func prepareAudioFile(for video: Video) -> Bool {
    do {
        audioFile = try AVAudioFile(forReading: video.url)
        if let file = audioFile {
            audioSampleRate = file.processingFormat.sampleRate
            audioLengthSamples = file.length
            return true
        }
        return false
    } catch {
        print("Failed to load audio file: \(error)")
        return false
    }
}
```

- Add retry with small delay if first attempt fails (file system timing)
- Set flag for UI notification if audio unavailable
- Only proceed to synchronized start when audio is confirmed ready

---

### 1.2 Ensure Engine is Fully Reset Between Tracks

**Location:** `startPlayback()` lines 217-218

**Problem:** `playerNode.stop()` alone may not fully clear scheduled buffers.

**Current code:**
```swift
// Stop current audio immediately to prevent transition "blips"
playerNode.stop()
```

**Solution:**
```swift
// Stop and fully reset audio node to clear any pending schedules
playerNode.stop()
playerNode.reset()  // ADD THIS

// Ensure engine is running
if !engine.isRunning {
    try? engine.start()
}
```

---

### 1.3 Sequential Audio/Video Preparation

**Location:** `startPlayback()` lines 249-256

**Problem:** Subscribing to `playerItem.status` before `audioFile` is ready creates a race condition.

**Current flow:**
```
1. Create playerItem
2. Load audioFile (sync)
3. Subscribe to playerItem.status
4. When .readyToPlay → prerollAndStartSynchronized
```

**Fixed flow:**
```
1. Load and validate audioFile (sync)
2. If failed, retry once after 100ms
3. Create playerItem
4. Subscribe to playerItem.status
5. When .readyToPlay AND audioFile ready → prerollAndStartSynchronized
```

---

### 1.4 Add State Validation Before Synchronized Start

**Location:** `prerollAndStartSynchronized()` at line 273

**Problem:** No validation that all components are ready.

**Solution - add guards:**
```swift
private func prerollAndStartSynchronized(from time: CMTime) {
    // Validate audio is ready (unless video-only mode)
    guard let file = audioFile else {
        // Handle video-only playback
        playVideoOnly(from: time)
        return
    }

    // Ensure engine is healthy
    guard engine.isRunning else {
        try? engine.start()
        guard engine.isRunning else {
            print("ERROR: Cannot start audio engine")
            playVideoOnly(from: time)
            return
        }
    }

    // ... rest of method
}
```

---

## Phase 2: Fix A/V Sync

### 2.1 Compensate for Audio Output Latency

**Location:** `prerollAndStartSynchronized()` lines 324-341

**Problem:** Audio has ~20-50ms output latency through AVAudioEngine that causes video to appear ahead.

**Current code:**
```swift
let startHostTime = hostTimeNow + delayHostTicks

// Start audio at precise host time
let audioStartTime = AVAudioTime(hostTime: startHostTime)
playerNode.play(at: audioStartTime)

// Start video at the same precise host time
let cmHostTime = CMClockMakeHostTimeFromSystemUnits(startHostTime)
player.setRate(1.0, time: time, atHostTime: cmHostTime)
```

**Solution:**
```swift
let startHostTime = hostTimeNow + delayHostTicks

// Query actual audio output latency
let outputLatency = AVAudioSession.sharedInstance().outputLatency
let latencyHostTicks = UInt64(outputLatency * 1_000_000_000 / nanosPerHostTick)

// Start audio at base host time
let audioStartTime = AVAudioTime(hostTime: startHostTime)
playerNode.play(at: audioStartTime)

// Start video LATER by the output latency amount
// This compensates for audio traveling through the output buffer
let videoStartHostTime = startHostTime + latencyHostTicks
let cmHostTime = CMClockMakeHostTimeFromSystemUnits(videoStartHostTime)
player.setRate(1.0, time: time, atHostTime: cmHostTime)
```

---

### 2.2 Use Host Time Sync in resyncAudio()

**Location:** `resyncAudio()` lines 514-524

**Problem:** After rescheduling, `playerNode.play()` starts immediately without host time alignment, causing sync drift.

**Current code:**
```swift
// 4. Resume if it was playing
if wasPlaying {
    if !engine.isRunning { try? engine.start() }
    playerNode.play()
}
```

**Solution:**
```swift
// 4. Resume if it was playing, with precise timing
if wasPlaying {
    if !engine.isRunning { try? engine.start() }

    // Calculate a near-future host time for synchronized restart
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let nanosPerHostTick = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)

    let hostTimeNow = mach_absolute_time()
    let delayNanos: UInt64 = 30_000_000  // 30ms - enough for scheduling
    let delayHostTicks = UInt64(Double(delayNanos) / nanosPerHostTick)
    let restartHostTime = hostTimeNow + delayHostTicks

    let audioRestartTime = AVAudioTime(hostTime: restartHostTime)
    playerNode.play(at: audioRestartTime)
}
```

---

### 2.3 Add Audio Prebuffering

**Location:** `prerollAndStartSynchronized()` before line 314

**Problem:** Video gets `preroll()` but audio has no equivalent buffering step.

**Solution:**
```swift
// Schedule audio segment
playerNode.scheduleSegment(file, startingFrame: targetSample, frameCount: remainingSamples, at: nil, completionHandler: nil)

// ADD: Prebuffer audio frames for smooth start
playerNode.prepare(withFrameCount: 8192)  // ~170ms at 48kHz
```

This preloads audio buffers before the synchronized start, matching video's preroll behavior.

---

### 2.4 Tighten Sync Threshold

**Location:** Line 38

**Current:**
```swift
private let syncThresholdSeconds: Double = 0.04  // 40ms
```

**Solution:**
```swift
private let syncThresholdSeconds: Double = 0.025  // 25ms - tighter threshold
```

25ms is:
- Still above typical system jitter (~5-10ms)
- Below human lip-sync perception threshold (~45ms)
- Catches drift faster while avoiding unnecessary resyncs

---

## Phase 3: Robustness Improvements

### 3.1 Add Audio Engine Health Check

**New method:**
```swift
/// Validates and repairs audio engine state if needed
private func ensureAudioEngineHealthy() -> Bool {
    // Check if engine is running
    guard engine.isRunning else {
        do {
            try engine.start()
            return engine.isRunning
        } catch {
            print("Failed to start audio engine: \(error)")
            return false
        }
    }

    // Verify nodes are properly attached
    // (engine.attachedNodes contains playerNode and eqNode)

    return true
}
```

Call this at the start of `startPlayback()` and before `prerollAndStartSynchronized()`.

---

### 3.2 Add Retry Logic for Track Transitions

**Location:** `startPlayback()` after audioFile loading

```swift
// Attempt to load audio file with retry
var audioReady = prepareAudioFile(for: video)
if !audioReady {
    // Wait briefly and retry once (file system timing)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        audioReady = self?.prepareAudioFile(for: video) ?? false
        if !audioReady {
            print("WARNING: Playing video without audio")
            // Optionally set flag for UI indicator
        }
        self?.continuePlaybackSetup(audioReady: audioReady)
    }
    return
}
continuePlaybackSetup(audioReady: true)
```

---

### 3.3 Add Detailed Logging for Debugging

**Add conditional logging (DEBUG builds):**

```swift
#if DEBUG
private func logSync(_ message: String) {
    let timestamp = Date().timeIntervalSince1970
    print("[SYNC \(String(format: "%.3f", timestamp))]: \(message)")
}
#else
private func logSync(_ message: String) {}
#endif
```

Log at key points:
- Audio file load success/failure with URL
- Engine state at transitions
- Actual sync delta when resync triggers
- Host time values used for synchronized start
- Output latency value being compensated

---

## Implementation Order

| Priority | Phase | Task | Impact | Effort |
|----------|-------|------|--------|--------|
| 1 | 1.2 | Engine reset (`playerNode.reset()`) | High | Low |
| 2 | 1.1 | Audio file validation | High | Medium |
| 3 | 2.1 | Output latency compensation | High | Medium |
| 4 | 2.2 | Host time in resyncAudio | Medium | Medium |
| 5 | 1.3 | Sequential preparation | Medium | Medium |
| 6 | 2.3 | Audio prebuffering | Medium | Low |
| 7 | 1.4 | State validation guards | Low | Low |
| 8 | 3.1 | Engine health check | Low | Medium |
| 9 | 2.4 | Tighten threshold | Low | Low |
| 10 | 3.2 | Retry logic | Low | Medium |
| 11 | 3.3 | Debug logging | Low | Low |

---

## Testing Checklist

Wait user to test it and provide feedback.

---

## Files to Modify

| File | Changes |
|------|---------|
| [PlayerViewModel.swift](Vid/ViewModels/PlayerViewModel.swift) | All sync and audio loading fixes |

No new files required. All changes are contained within PlayerViewModel.
