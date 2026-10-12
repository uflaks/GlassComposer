# Device testing

What the simulator and the test suites cannot prove, with the behaviour each
check should show. Everything through 0.7.0 was verified by build, lint,
`swift test` and the iOS Simulator suites only; the items below need a real
iPhone (iOS 26) or a Mac (macOS 26). The Example app
(`Example/ComposerShots`, iOS and macOS) covers everything below; a real
chat app that plays audio is better for the audio-session items.

Tick an item when it passes. If it fails, note the device, OS build and
what happened next to it.

## Dictation

- [ ] **Basic dictation.** Tap the mic, speak a sentence, tap again.
  Expect: mic turns red while recording, live text appears in the field as
  you speak, final text stays after stopping, existing draft text is kept
  with a single space before the spoken part.
- [ ] **Microphone denied.** Fresh install, deny the microphone prompt.
  Expect: red "Microphone permission is required." above the field,
  `failure == .microphoneDenied`, mic icon not red.
- [ ] **Speech recognition denied.** Fresh install, allow the mic, deny
  speech recognition. Expect: "Speech recognition permission is required.",
  `failure == .speechDenied`.
- [ ] **Explicit locale.** Construct the controller with a locale that is
  not the device language, for example `Locale(identifier: "nb-NO")` on an
  English phone. Expect: the first start downloads the on-device model (a
  pause of several seconds on Wi-Fi), then transcribes Norwegian. Changing
  `locale` between recordings switches language on the next start. While
  the model downloads the mic shows a spinner (`isPreparing`), not red.
- [ ] **Model download offline.** Same as above with Wi-Fi and cellular off
  and the model not yet installed. Expect: "Could not download the
  on-device speech model…", `failure == .assetUnavailable` (before 0.8.0
  this surfaced as `.audioSetupFailed`), no hung recording state.
- [ ] **Unsupported locale.** Pass a locale `SpeechAnalyzer` has no model
  for. Expect: "Speech recognition is not available for this language.",
  `failure == .localeNotSupported`.

- [ ] **Double tap.** Tap the mic twice quickly. Expect: dictation ends up
  off (the second tap cancels the first start), never on.
- [ ] **Dropped mid-recording.** Start dictation, then navigate away so the
  view owning the controller is destroyed. Expect: the orange microphone
  indicator in the status bar goes away within a second.
- [ ] **Speech authorization is needed at all.** On-device
  `SpeechTranscriber` may not require `SFSpeechRecognizer` authorization. If
  denying it still lets dictation work, the `.speechDenied` gate and the
  `NSSpeechRecognitionUsageDescription` requirement can both go.

## Audio session (iOS only)

- [ ] **Restore after dictation, default policy.** In a host that plays
  audio through an `AVAudioSession` set to `.playback`: start playback, start dictation,
  stop dictation, start playback again. Expect: playback pauses or ducks
  while recording, and plays normally again afterwards without the host
  reconfiguring its session. Before 0.6.0 the session was left on
  `.record` and playback failed.
- [ ] **`.managed(category: .playAndRecord)`.** Same host, controller built
  with that policy. Expect: playback keeps going (ducked) while dictating.
- [ ] **`.hostManaged`.** Host sets up its own `.playAndRecord` session and
  activates it, controller built with `.hostManaged`. Expect: dictation
  works, and the host's category is untouched before, during and after.
- [ ] **Phone call during dictation.** Start dictation, receive a call (or
  trigger Siri, or let an alarm fire). Expect: recording stops by itself,
  mic icon returns to normal, `isRecording == false`, no error shown. After
  the interruption ends, tapping the mic starts a new recording.
- [ ] **Route change during dictation.** Start dictation on AirPods, put
  them in the case (or unplug wired headphones). Expect: recording stops
  cleanly as above. Also try the reverse, connecting AirPods mid-recording.
- [ ] **Background.** Start dictation, press Home, come back. Expect: either
  recording continues or it stopped cleanly; never a red mic with no audio
  flowing.

## Attachments (the Example app's `empty` state has the picker)

- [ ] **Large photo.** Attach a 48 MP photo. Expect: the paperclip caption
  appears, the UI stays responsive while encoding (scroll the list), and the
  attached JPEG is at most 1536 px on its long edge and under 750 KB.
- [ ] **Fast re-pick.** Pick an iCloud-only photo, then immediately pick a
  local one. Expect: the local one is attached; the slow first pick never
  replaces it.
- [ ] **Custom policy.** Build the state with
  `ComposerAttachmentPolicy(maxPixelDimension: 4096, maxJPEGByteCount: 5_000_000)`.
  Expect: the same photo comes through larger.
- [ ] **iCloud photo offline.** Airplane mode, pick a photo that is only in
  iCloud (greyed thumbnail). Expect: "Couldn't load that photo.",
  `failure == .unavailable`.
- [ ] **Live Photo, HEIC, PNG screenshot, RAW.** Each should attach as a
  JPEG with correct orientation (take a portrait photo and check it is not
  rotated).
- [ ] **Corrupt item.** Hard to provoke from Photos; `failure == .notAnImage`
  is reachable only when Photos hands over bytes ImageIO cannot decode. If
  you have such an item, expect "That file isn't an image the composer can
  send."

## Composer UI

- [ ] **Leading toggle.** The Example app's `empty` state has one. Expect: globe tints with the accent colour when on, taps toggle it, a
  selection haptic fires on each change.
- [ ] **VoiceOver.** Turn VoiceOver on and swipe through the composer.
  Expect: "Open menu", the toggle's label with "On" or "Off", the field's
  placeholder, "Start speech input", "Send" (dimmed while empty). While a
  turn runs with `onStop` set: "Stop".
- [ ] **Plus menu.** Open with `+`, tap outside to dismiss, open again and
  pick Photos. Expect: the icon rotates to an ×, the dim backdrop catches
  the outside tap, picking a photo closes the menu, and focusing the text
  field closes it too.
- [ ] **Touches over the list.** With the composer mounted over a scrolled
  chat, tap the padding between `+` and the field, and the gap next to the
  send button. Expect: nothing underneath receives the tap.
- [ ] **Growing field.** Paste eight lines. Expect: the field grows to six
  lines then scrolls, the controls stay bottom-aligned, the glass shape
  stays rounded.
- [ ] **Send and stop.** Type, press send: medium haptic, text cleared by
  the host. While a turn runs with `onStop`: the stop button replaces send
  and calls `onStop`.
- [ ] **Dark mode and Reduce Transparency.** Toggle both in Settings.
  Expect: glass stays legible over scrolled text in both; with Reduce
  Transparency the controls fall back to opaque material without clipping.
- [ ] **Dynamic Type.** Largest accessibility size. Expect: field and menu
  rows grow, round controls keep their 44 pt size, nothing overlaps.
- [ ] **Localization fallback.** Set the device to a language the catalog
  does not have (anything but English). Expect: the built-in strings show
  in English, never as raw keys, and host-supplied strings show in the
  host's language.

## macOS (the Example app's Mac destination)

- [ ] **Shapes.** `+`, accessory, send and stop are all 44 pt glass
  circles; the accessory `Menu` shows no chevron and no pill.
- [ ] **Keyboard.** Expected from the code, unverified: Return sends,
  Option-Return inserts a newline, ⌘Return sends too, and a click outside
  closes the `+` menu. On iPhone Return inserts a newline and never sends.
- [ ] **Microphone in a sandboxed app.** App has the Audio Input
  entitlement and the two usage strings. Expect: the system mic prompt
  appears once, then dictation works. Without the entitlement expect
  `.audioSetupFailed`, not a hang.
- [ ] **No input device / no entitlement.** Expected `.audioSetupFailed`;
  accessing the engine's input node without the entitlement may instead
  raise an Objective-C exception. If it crashes, that is a bug to fix.
- [ ] **Display change.** Start dictation, change the audio input device in
  System Settings. Expect: recording stops cleanly (engine configuration
  change).

## After a release

- [ ] `scripts/screenshots.sh` still produces the six README images
  without visual regressions.
- [ ] A fresh consumer (new Xcode project, add the package by URL) builds,
  shows the composer, and dictates, with nothing but the two Info.plist
  keys added.
