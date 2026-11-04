{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Keep every request on this origin. The app bundles its own fonts and
    // serves the Noto Sans subset that Yoruba and Igbo names need from
    // web/fallback-fonts/, so the engine never fetches from a CDN.
    fontFallbackBaseUrl: "fallback-fonts/",
  },
});
