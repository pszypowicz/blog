+++
title       = "macOS 27 stops trackpad touch events after a lid-open or trackpad-click wake"
date        = "2026-09-29T12:00:00+02:00"
description = "On macOS 27.0.1, if you open the lid or click the trackpad to wake the Mac, apps that started before the sleep lose NSTouch events. Scroll and magnify events still arrive, and a power-button wake brings the touches back."
tags        = ["macos", "appkit", "trackpad", "tmux"]
categories  = ["macos"]
ai_assisted = true
+++

On macOS 27.0.1, if you open the lid or click the trackpad to wake the Mac, apps that started before the sleep lose trackpad touch events. This post lists the facts, the workarounds and the limits of my tests.

## Environment

- MacBook Pro with Apple M1 Pro (MacBookPro18,1) and the built-in trackpad
- macOS 27.0.1 (26A434)

## Symptom

- The app receives no `NSTouch` events. `touchesBegan(with:)` and `touchesMoved(with:)` are not called, and a local `NSEvent` monitor for `.gesture` events sees no touches.
- Scroll events, magnify events and smart magnify (two-finger double-tap) still arrive.
- The fault applies to the whole process. A new window does not help, and a restart of the app fixes it.
- An app that starts after the wake receives touch events normally.
- A minimal AppKit app with one view shows the same result, so the fault is in macOS.

In my setup, a [Ghostty fork](https://github.com/pszypowicz/ghostty) reads raw touches with [TrackpadKit](https://github.com/pszypowicz/TrackpadKit) and sends swipe and pinch gestures to a [tmux fork](https://github.com/pszypowicz/tmux). After a wake, the swipe between tmux windows stopped.

## Wake results

In every test, the test app started before the sleep.

| Wake method             | From the normal state | From the broken state |
| ----------------------- | --------------------- | --------------------- |
| Trackpad click          | touches stop          | stays broken          |
| Lid open                | touches stop          | not tested            |
| Key press               | touches continue      | stays broken          |
| Power button (Touch ID) | not tested            | touches return        |

At the power-button wake, the terminal, which was broken at the same time, recovered too.

## Events in the broken state

| Event                                            | Result                    |
| ------------------------------------------------ | ------------------------- |
| `touchesBegan(with:)`, `touchesMoved(with:)`     | 0                         |
| `scrollWheel(with:)` during a two-finger swipe   | about 110 per second      |
| `magnify(with:)` during a pinch                  | about 40 to 50 per second |
| `smartMagnify(with:)` on a two-finger double-tap | works                     |
| `swipe(with:)`                                   | 0 in every test           |

## Workarounds

- Wake the Mac with a key press. In the tests, a trackpad-click wake and a lid-open wake both stopped the touches.
- If the gestures already stopped, run `pmset sleepnow` and wake the Mac with the power button.
- As a last resort, restart the app. With tmux, the sessions survive a terminal restart.

## What does not help inside the app

None of these actions brings the touch events back:

- Set `allowedTouchTypes` to `[]` and back to `[.indirect]`, in one run loop turn and with 0.5 seconds between the calls.
- Remove the view from the window and add it again.
- Call `orderOut(_:)` and then `makeKeyAndOrderFront(_:)` on the window.
- Open a new window with a new view that accepts touches.
- Hide and unhide the app.

## Notes for developers

- To detect the broken state, look for scroll events with a phase and no touch frames for the same gesture.
- As a fallback, take pinch from `magnify(with:)`, and take a horizontal swipe from scroll events and their phases.
- Do not use `swipe(with:)` as a fallback. It did not fire in any test.

## Repro

The view of the test app:

```swift
final class TouchView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func touchesBegan(with event: NSEvent) { counters.touches += 1 }
    override func touchesMoved(with event: NSEvent) { counters.touches += 1 }
    override func scrollWheel(with event: NSEvent) { counters.scroll += 1 }
    override func magnify(with event: NSEvent) { counters.magnify += 1 }
}
// A 1-second timer prints and resets the counters.
```

1. Start the test app and put the pointer over its window.
2. Move two fingers on the trackpad.
3. Run `pmset sleepnow` and wait 15 seconds.
4. Wake the Mac with a trackpad click.
5. Move two fingers on the trackpad again.

Before the sleep, the app prints about 100 touch events per second. After the wake, it prints 0.

## Limits of the tests

- I tested only the built-in trackpad. I did not test a Magic Trackpad.
- I did not test a Touch ID wake from the normal state or a wake with an external display.
- One earlier failure came after a normal wake, with an unknown wake method.

I reported the problem to Apple in Feedback Assistant.
