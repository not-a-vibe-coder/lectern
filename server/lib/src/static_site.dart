import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'api.dart';
import 'keys.dart';

class _CachedFile {
  _CachedFile(this.modified, this.length, this.bytes, this.gzipped);
  final DateTime modified;
  final int length;
  final List<int> bytes;
  final List<int>? gzipped;
}

/// Serves the built Flutter web app with:
/// * ETags and `no-cache` revalidation for app files, long caching for fonts
///   and CanvasKit;
/// * gzip for text and wasm when the browser accepts it (students are on
///   mobile data);
/// * single-page-app fallback to `index.html`, with shelf-specific titles and
///   Open Graph tags so links shared in WhatsApp groups preview well.
class StaticSite {
  StaticSite(this.ctx) : root = p.normalize(p.absolute(ctx.config.webDir));

  final AppContext ctx;
  final String root;
  final _cache = <String, _CachedFile>{};

  static const _compressible = {
    'text/html',
    'text/css',
    'text/plain',
    'application/javascript',
    'text/javascript',
    'application/json',
    'application/manifest+json',
    'image/svg+xml',
    'application/wasm',
    'font/ttf',
    'application/x-font-ttf',
    'font/otf',
  };

  Future<Response> handle(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, body: 'Method not allowed');
    }
    final segments = request.url.pathSegments;
    if (segments.any((s) => s == '..' || s.startsWith('.'))) {
      return Response.notFound('Not found');
    }
    final relative = segments.join('/');
    if (relative.isEmpty) {
      final landing = await _serveLanding(request);
      if (landing != null) return landing;
    }
    if (relative.isNotEmpty && relative != 'index.html') {
      final file = File(p.join(root, relative));
      if (p.isWithin(root, file.path) && await _isPublicFile(file)) {
        return _serveFile(request, file, relative);
      }
      if (_fallbackFontPath.hasMatch(relative)) {
        final standIn = await _missingFallbackFont();
        if (standIn != null) return standIn;
      }
      // A missing file with an extension is a real 404, not an app route.
      if (p.extension(relative).isNotEmpty) {
        return Response.notFound('Not found');
      }
    }
    return _serveIndex(request);
  }

  /// A fallback font the Flutter engine asks for when text has characters
  /// the bundled fonts lack (`fontFallbackBaseUrl` in
  /// `web/flutter_bootstrap.js`), for example
  /// `fallback-fonts/notosanssc/v37/<id>.118.woff2`.
  static final _fallbackFontPath = RegExp(
    r'^fallback-fonts/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_.-]+[.]woff2$',
  );

  /// The answer for fallback fonts this server does not bundle (CJK, Arabic
  /// and other scripts): `fallback-fonts/missing.woff2`, a valid font with no
  /// glyphs. The engine retries a failed font download every time it lays
  /// the text out again, hundreds of times in a few seconds of typing; a font
  /// it can load stops that. The characters show as boxes and nothing is
  /// fetched from a font CDN. Null (a plain 404) if the build lacks the file.
  Future<Response?> _missingFallbackFont() async {
    final file = File(p.join(root, 'fallback-fonts', 'missing.woff2'));
    if (!await _isPublicFile(file)) return null;
    final entry = await _load(file, 'font/woff2');
    return Response.ok(
      entry.bytes,
      headers: {
        'content-type': 'font/woff2',
        'cache-control': 'public, max-age=86400',
        'x-lectern-font': 'no-glyphs',
      },
    );
  }

  Future<bool> _isPublicFile(File file) async {
    try {
      final realRoot = await Directory(root).resolveSymbolicLinks();
      final realFile = await file.resolveSymbolicLinks();
      return p.isWithin(realRoot, realFile) && await file.exists();
    } on FileSystemException {
      return false;
    }
  }

  bool _acceptsGzip(Request request) {
    double? wildcard;
    for (final entry in (request.headers['accept-encoding'] ?? '').split(',')) {
      final parts = entry.trim().toLowerCase().split(';');
      final encoding = parts.first.trim();
      var quality = 1.0;
      for (final parameter in parts.skip(1)) {
        final pair = parameter.trim().split('=');
        if (pair.length == 2 && pair.first.trim() == 'q') {
          quality = double.tryParse(pair.last.trim()) ?? 0;
        }
      }
      if (encoding == 'gzip') return quality > 0 && quality <= 1;
      if (encoding == '*') wildcard = quality;
    }
    return wildcard != null && wildcard > 0 && wildcard <= 1;
  }

  Future<_CachedFile> _load(File file, String mime) async {
    final stat = await file.stat();
    final cached = _cache[file.path];
    if (cached != null &&
        cached.modified == stat.modified &&
        cached.length == stat.size) {
      return cached;
    }
    final bytes = await file.readAsBytes();
    final gz = _compressible.contains(mime) && bytes.length > 1024
        ? gzip.encode(bytes)
        : null;
    final entry = _CachedFile(stat.modified, stat.size, bytes, gz);
    // Large files such as CanvasKit are cached too; the whole build is a few
    // megabytes.
    _cache[file.path] = entry;
    return entry;
  }

  Future<Response> _serveFile(
    Request request,
    File file,
    String relative,
  ) async {
    final mime = _mimeFor(relative);
    final entry = await _load(file, mime);
    final etag =
        '"${entry.modified.millisecondsSinceEpoch.toRadixString(36)}-'
        '${entry.length.toRadixString(36)}"';
    // Only hand-made files that keep their content for a given URL are
    // cached without asking. Flutter's own output keeps its file names from
    // build to build (MaterialIcons-Regular.otf is re-cut to the icons each
    // build uses; canvaskit/ follows the Flutter version), so it is
    // revalidated with the ETag: a 304 costs a few hundred bytes, a stale
    // icon font costs missing icons.
    // fallback-fonts/ paths carry a version and a hash, so they never change.
    final longLived =
        relative.startsWith('assets/assets/fonts/') ||
        relative.startsWith('fallback-fonts/') ||
        relative.startsWith('landing/fonts/') ||
        relative.startsWith('landing/img/');
    final headers = <String, String>{
      'content-type': mime,
      'etag': etag,
      'cache-control': longLived ? 'public, max-age=604800' : 'no-cache',
      'vary': 'accept-encoding',
    };
    if (request.headers['if-none-match'] == etag) {
      return Response.notModified(headers: headers);
    }
    final acceptsGzip = _acceptsGzip(request);
    final body = acceptsGzip && entry.gzipped != null
        ? entry.gzipped!
        : entry.bytes;
    if (acceptsGzip && entry.gzipped != null) {
      headers['content-encoding'] = 'gzip';
    }
    headers['content-length'] = '${body.length}';
    return Response.ok(
      request.method == 'HEAD' ? null : body,
      headers: headers,
    );
  }

  String _mimeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.js' || '.mjs' => 'application/javascript',
      '.wasm' => 'application/wasm',
      '.json' => 'application/json',
      '.webmanifest' => 'application/manifest+json',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf',
      '.woff2' => 'font/woff2',
      '.woff' => 'font/woff',
      '.svg' => 'image/svg+xml',
      '.html' => 'text/html',
      _ => lookupMimeType(path) ?? 'application/octet-stream',
    };
  }

  /// The static landing page at `/`: plain HTML, no Flutter, so it loads
  /// fast on mobile data. `{{ORIGIN}}` becomes the public origin for canonical
  /// and Open Graph URLs.
  Future<Response?> _serveLanding(Request request) async {
    final file = File(p.join(root, 'landing', 'index.html'));
    if (!await _isPublicFile(file)) return null;
    final template = utf8.decode((await _load(file, 'text/html')).bytes);
    final html = template.replaceAll(
      '{{ORIGIN}}',
      const HtmlEscape(HtmlEscapeMode.attribute).convert(ctx.origin(request)),
    );
    final bytes = utf8.encode(html);
    final acceptsGzip = _acceptsGzip(request);
    final body = acceptsGzip ? gzip.encode(bytes) : bytes;
    return Response.ok(
      request.method == 'HEAD' ? null : body,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
        'vary': 'accept-encoding',
        if (acceptsGzip) 'content-encoding': 'gzip',
        'content-length': '${body.length}',
      },
    );
  }

  Future<Response> _serveIndex(Request request) async {
    final file = File(p.join(root, 'index.html'));
    if (!await _isPublicFile(file)) {
      return Response(
        503,
        body:
            'The web app is not built yet. Run `flutter build web` in app/ '
            'or set WEB_DIR.',
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }
    final template = utf8.decode((await _load(file, 'text/html')).bytes);
    final html = template.replaceFirst(
      RegExp(r'<!-- lectern:meta -->[\s\S]*?<!-- /lectern:meta -->'),
      _metaFor(request),
    );
    final bytes = utf8.encode(html);
    final acceptsGzip = _acceptsGzip(request);
    final body = acceptsGzip ? gzip.encode(bytes) : bytes;
    return Response.ok(
      request.method == 'HEAD' ? null : body,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
        'vary': 'accept-encoding',
        if (acceptsGzip) 'content-encoding': 'gzip',
        'content-length': '${body.length}',
      },
    );
  }

  String _metaFor(Request request) {
    final origin = ctx.origin(request);
    final segments = request.url.pathSegments;
    var title = 'Lectern';
    var description =
        'Lecture notes and past questions for your course, shared by your '
        'course rep.';
    var url = '$origin/';
    var index = true;

    if (segments.length >= 2 && segments[0] == 's' && isValidId(segments[1])) {
      index = false;
      final shelf = ctx.store.getShelf(segments[1]);
      if (shelf != null) {
        url = '$origin/s/${Uri.encodeComponent(shelf.id)}';
        title = '${shelf.title} · Lectern';
        final count = ctx.store.countVisibleItems(shelf.id);
        description = count == 0
            ? 'Lecture notes and past questions for ${shelf.title}.'
            : '$count ${count == 1 ? 'file' : 'files'}: lecture notes, past '
                  'questions and assignments for ${shelf.title}.';
        if (segments.length >= 4 &&
            segments[2] == 'i' &&
            isValidId(segments[3])) {
          final item = ctx.store.getItem(shelf.id, segments[3]);
          if (item != null && !item.hidden) {
            title = '${item.courseCode} · ${item.title} · Lectern';
            description =
                '${item.type.label} for ${item.courseCode}, '
                'shared on ${shelf.title}.';
            url =
                '$origin/s/${Uri.encodeComponent(shelf.id)}'
                '/i/${Uri.encodeComponent(item.id)}';
          }
        }
        if (segments.length >= 3 && segments[2] == 'manage') {
          title = 'Manage ${shelf.title} · Lectern';
          url = '$origin/s/${Uri.encodeComponent(shelf.id)}';
        }
      } else {
        title = 'Shelf not found · Lectern';
      }
    }

    String esc(String s) =>
        const HtmlEscape(HtmlEscapeMode.attribute).convert(s);
    return [
      '<!-- lectern:meta -->',
      '<title>${esc(title)}</title>',
      '<meta name="description" content="${esc(description)}">',
      '<meta property="og:type" content="website">',
      '<meta property="og:site_name" content="Lectern">',
      '<meta property="og:title" content="${esc(title)}">',
      '<meta property="og:description" content="${esc(description)}">',
      '<meta property="og:url" content="${esc(url)}">',
      '<meta property="og:image" content="${esc('$origin/og-image.png')}">',
      '<meta property="og:image:width" content="1200">',
      '<meta property="og:image:height" content="630">',
      '<meta name="twitter:card" content="summary_large_image">',
      if (!index) '<meta name="robots" content="noindex">',
      '<!-- /lectern:meta -->',
    ].join('\n  ');
  }
}
