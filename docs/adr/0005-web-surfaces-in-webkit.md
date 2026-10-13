# Animated surfaces are web pages in WKWebView, drawn with Canvas or WebGL

The Briefing tab (React), the island show and the welcome (canvas) are built in `Web/` and shown in WKWebView. The island and the welcome are single-file HTML bundles committed into the app's resources, so the app builds without npm. They are drawn with Canvas 2D or WebGL, never SVG filters: WebKit runs SVG reference filters on the CPU at Retina size, which held the island show to 14 fps until the goo moved to WebGL (58 fps). Each page measures its own fps and posts it back, and the app logs it.
