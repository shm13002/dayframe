# Web: Prettier everywhere, and a test that pins the shared palette values
Status: ready-for-agent
Type: task

Format `Web/` with Prettier (printWidth 120). Add a Vitest test that reads `DayframePalette.swift` and checks that the Original palette's stops match `paletteStops("original")`, so the Swift and web copies can't drift. Add tests for the island's pure timeline and layout functions.
