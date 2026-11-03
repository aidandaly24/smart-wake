# Original wake-up games

New sessions offer three short puzzle styles. Daily rotation cycles by the **target wake-up date in the plan's saved time zone**, rather than by when the app opens. A different style can also be selected before arming. The selected puzzle and progress are saved with the existing alarm session, so a midnight boundary or a relaunch cannot swap an unfinished puzzle.

- **Five-letter word:** enter guesses and read exact-position, elsewhere, and absent feedback. Repeated letters are scored against the remaining letters, not just whether a letter occurs anywhere. A clue and progressive hints keep it wake-friendly.
- **Find the groups:** choose four related words at a time from a compact original board. Solved groups remain visible. A wrong set costs no lives.
- **Mini crossword:** choose an Across or Down clue, enter its answer, and fill a compact intersecting grid. Correct answers and their crossing letters remain visible.

All words, group themes and clues are an original bundled starter collection, not imported from commercial daily games. This finite collection rotates; it is not a promise of a new never-repeated puzzle every day. There is no network puzzle service, login, timer, paid content or real health data in the puzzle catalog.

## Safety and persistence

- Solving the whole puzzle persists the completed session and cancellation ledger before requesting AlarmKit cancellation.
- The adapter still checks that this app's remaining alarms are gone before reporting success. Cancellation errors retain the session for retry.
- Hints do not silently finish the session. The answer still needs to be submitted.
- An emergency-stop button stays pinned below the puzzle, including during long boards or keyboard entry. Leaving the puzzle does not cancel reminders.
- Existing saved memory-game sessions continue in that game; the new styles apply when a new alarm session is armed. Do not replace an existing session merely to change its game.
- The games use the shared scheduler for bounded one-minute reminders and the latest fallback. iOS system Stop remains available. Keep a trusted separate alarm during testing.

## Verification required on a Mac

Run `swift test` from the project folder. Then compile the iPhone and Watch schemes using the installed SDKs. Test each style through the pre-alarm game picker, including wrong/duplicate input, hint use, relaunch midway, final completion, and an emergency stop before completion. Confirm that cancellation failure does not claim that alarms stopped.

The cloud workspace has no Swift or Apple SDK toolchain. Structural checks and source review are not proof of native compilation or device behavior.
