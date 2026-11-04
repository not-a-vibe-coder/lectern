import 'dart:convert';

import 'package:qr/qr.dart';
import 'package:shelf/shelf.dart';

import 'api.dart';
import 'keys.dart';

/// Builds an SVG path for a QR code, merging horizontal runs of dark modules.
String qrSvg(String data, {String color = '#141A2E', int quiet = 4}) {
  final code = QrCode(
    payload: QrPayload.fromString(data),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  final image = QrImage(code);
  final n = image.moduleCount;
  final d = StringBuffer();
  for (var y = 0; y < n; y++) {
    var x = 0;
    while (x < n) {
      if (!image.isDark(y, x)) {
        x++;
        continue;
      }
      final start = x;
      while (x < n && image.isDark(y, x)) {
        x++;
      }
      d.write('M${start + quiet} ${y + quiet}h${x - start}v1h-${x - start}z');
    }
  }
  final size = n + quiet * 2;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" '
      'shape-rendering="crispEdges" role="img" aria-label="QR code">'
      '<rect width="$size" height="$size" fill="#fff"/>'
      '<path fill="$color" d="$d"/></svg>';
}

/// A print-ready A4 poster with the shelf's QR code, at `/s/<id>/print`.
///
/// It is plain HTML rather than a Flutter screen because browsers print HTML
/// reliably, and reps can send this link straight to a print shop.
class PosterPage {
  PosterPage(this.ctx);
  final AppContext ctx;

  Response handle(Request request, String shelfId) {
    final shelf = isValidId(shelfId) ? ctx.store.getShelf(shelfId) : null;
    if (shelf == null) {
      return Response.notFound(
        _page(
          title: 'Shelf not found',
          body:
              '<main class="missing"><h1>This shelf does not exist.</h1>'
              '<p>Check the link and try again.</p></main>',
        ),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    final url = '${ctx.origin(request)}/s/${Uri.encodeComponent(shelf.id)}';
    final shortUrl = url.replaceFirst(RegExp(r'^https?://'), '');
    final esc = const HtmlEscape(HtmlEscapeMode.element).convert;
    final autoPrint = request.url.queryParameters['print'] == '1';
    final body =
        '''
<div class="toolbar">
  <a href="/s/${Uri.encodeComponent(shelf.id)}">Back to shelf</a>
  <button type="button" onclick="window.print()">Print poster</button>
</div>
<main class="sheet">
  <div class="margin" aria-hidden="true"></div>
  <header>
    <p class="eyebrow">Course materials</p>
    <h1>${esc(shelf.title)}</h1>
    <p class="lede">Lecture notes, past questions and assignments, shared by your course rep.</p>
  </header>
  <section class="code">
    ${qrSvg(url)}
    <p class="url">${esc(shortUrl)}</p>
  </section>
  <ol class="steps">
    <li><b>Open your phone camera</b> or any QR scanner.</li>
    <li><b>Point it at the code</b> above.</li>
    <li><b>Tap the link</b> to open the shelf. No sign-up needed.</li>
  </ol>
  <footer>
    <span>Lectern</span><span>Files stored on Walrus</span><span>Built with Dartus</span>
  </footer>
</main>
${autoPrint ? '<script>window.addEventListener("load",()=>setTimeout(()=>window.print(),300));</script>' : ''}
''';
    return Response.ok(
      _page(title: 'Print QR poster · ${shelf.title}', body: body),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
      },
    );
  }

  String _page({required String title, required String body}) {
    final esc = const HtmlEscape(HtmlEscapeMode.element).convert;
    return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${esc(title)}</title>
<link rel="icon" href="/favicon.png" type="image/png">
<style>
@font-face{font-family:Newsreader;font-weight:600;src:url(/assets/assets/fonts/Newsreader-SemiBold.ttf) format("truetype");}
@font-face{font-family:Atkinson;font-weight:400;src:url(/assets/assets/fonts/AtkinsonHyperlegible-Regular.ttf) format("truetype");}
@font-face{font-family:Atkinson;font-weight:700;src:url(/assets/assets/fonts/AtkinsonHyperlegible-Bold.ttf) format("truetype");}
@font-face{font-family:JetBrainsMono;font-weight:600;src:url(/assets/assets/fonts/JetBrainsMono-SemiBold.ttf) format("truetype");}
@page{size:A4 portrait;margin:0}
*{box-sizing:border-box}
html,body{margin:0;background:#E9E7DF;color:#141A2E;font-family:Atkinson,system-ui,sans-serif}
.toolbar{display:flex;gap:12px;justify-content:center;align-items:center;padding:16px}
.toolbar a{color:#2437C2;font-weight:700}
.toolbar button{font:700 16px Atkinson,system-ui,sans-serif;background:#2437C2;color:#fff;border:0;border-radius:6px;padding:12px 20px;cursor:pointer}
.toolbar button:focus-visible,.toolbar a:focus-visible{outline:3px solid #141A2E;outline-offset:2px}
.sheet{position:relative;width:210mm;min-height:297mm;margin:0 auto 32px;background:#fff;padding:22mm 20mm 16mm 30mm;display:flex;flex-direction:column;box-shadow:0 8px 24px rgba(20,26,46,.12)}
.margin{position:absolute;top:0;bottom:0;left:22mm;width:0;border-left:1.2px solid #E07A73}
.eyebrow{font:600 12pt JetBrainsMono,monospace;letter-spacing:.08em;text-transform:uppercase;margin:0 0 4mm;color:#2437C2}
h1{font:600 30pt/1.1 Newsreader,Georgia,serif;margin:0 0 4mm;letter-spacing:-.01em}
.lede{font-size:14pt;line-height:1.4;margin:0;color:#444B60}
.code{margin:14mm auto 8mm;text-align:center}
.code svg{width:105mm;height:105mm;display:block;margin:0 auto}
.url{font:600 15pt JetBrainsMono,monospace;margin:4mm 0 0;overflow-wrap:anywhere}
.steps{margin:4mm 0 0;padding-left:7mm;font-size:13pt;line-height:1.6}
.steps b{font-weight:700}
footer{margin-top:auto;padding-top:8mm;border-top:1px solid #D5DCEB;display:flex;justify-content:space-between;font-size:10pt;color:#5E6578}
.missing{max-width:520px;margin:15vh auto;padding:24px;text-align:center}
@media print{html,body{background:#fff}.toolbar{display:none}.sheet{margin:0;box-shadow:none}}
@media (max-width:820px){.sheet{transform-origin:top left;width:auto;min-height:auto;margin:0 12px 24px;padding:24px 20px 20px 36px}.margin{left:22px}.code svg{width:min(105mm,70vw);height:min(105mm,70vw)}h1{font-size:24pt}.url{font-size:12pt}}
</style>
</head>
<body>
$body
</body>
</html>''';
  }
}
