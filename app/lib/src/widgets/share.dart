import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../app_scope.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'press.dart';
import 'layout.dart';

/// A QR code drawn with the `qr` package.
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    this.size = 180,
    this.label,
  });
  final String data;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    return Semantics(
      image: true,
      label: label ?? 'QR code for $data',
      child: Container(
        color: Colors.white,
        width: size,
        height: size,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 3;
    final n = image.moduleCount;
    final cell = size.width / (n + quiet * 2);
    final paint = Paint()
      ..color = LecternColors.ink
      ..isAntiAlias = false;
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
        canvas.drawRect(
          Rect.fromLTWH(
            (start + quiet) * cell,
            (y + quiet) * cell,
            (x - start) * cell + 0.5,
            cell + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

String whatsAppShareUrl(String text) =>
    'https://wa.me/?text=${Uri.encodeComponent(text)}';

/// Share actions for a shelf: copy link, WhatsApp, the system share sheet
/// and the printable poster.
class ShareActions extends StatelessWidget {
  const ShareActions({
    super.key,
    required this.shelfId,
    required this.title,
    this.direction = Axis.vertical,
  });

  final String shelfId;
  final String title;
  final Axis direction;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final url = services.config.shelfUrl(shelfId);
    final message =
        '$title: lecture notes and past questions on Lectern. Open: $url';

    final buttons = <Widget>[
      FilledButton.icon(
        onPressed: () => copyText(context, url, message: 'Link copied'),
        icon: const Icon(Icons.link, size: 20),
        label: const Text('Copy link'),
      ),
      OutlinedButton.icon(
        onPressed: () => services.browser.openUrl(whatsAppShareUrl(message)),
        icon: const Icon(Icons.chat_outlined, size: 20),
        label: const Text('Share on WhatsApp'),
      ),
      if (services.browser.canShare)
        OutlinedButton.icon(
          onPressed: () => services.browser.share(
            title: title,
            text: '$title: lecture notes and past questions on Lectern.',
            url: url,
          ),
          icon: const Icon(Icons.ios_share, size: 20),
          label: const Text('More apps'),
        ),
      OutlinedButton.icon(
        onPressed: () =>
            services.browser.openUrl(services.config.posterUrl(shelfId)),
        icon: const Icon(Icons.print_outlined, size: 20),
        label: const Text('Print QR poster'),
      ),
    ];

    if (direction == Axis.horizontal) {
      return Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: pressable(buttons),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in pressable(buttons)) ...[
          b,
          const SizedBox(height: Space.xs),
        ],
      ],
    );
  }
}

/// QR code, link and share actions in one panel.
class SharePanel extends StatelessWidget {
  const SharePanel({super.key, required this.shelfId, required this.title});
  final String shelfId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final url = services.config.shelfUrl(shelfId);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Share with your class', style: text.titleMedium),
        const SizedBox(height: Space.xxs),
        Text(
          'Post the link in your class WhatsApp group, or show the code in a lecture.',
          style: text.bodySmall,
        ),
        const SizedBox(height: Space.md),
        Center(
          child: Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: LecternColors.rule),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: QrCodeView(
              data: url,
              size: 168,
              label: 'QR code that opens this shelf',
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        SelectableText(
          url.replaceFirst(RegExp(r'^https?://'), ''),
          textAlign: TextAlign.center,
          style: LecternType.mono.copyWith(color: LecternColors.ink),
        ),
        const SizedBox(height: Space.md),
        ShareActions(shelfId: shelfId, title: title),
      ],
    );
  }
}

/// Opens the share panel in a bottom sheet (phones) or a dialog (wider).
Future<void> showShareSheet(
  BuildContext context, {
  required String shelfId,
  required String title,
}) {
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
  final services = AppScope.of(context);
  Widget body(BuildContext context) => AppScope(
    services: services,
    child: SharePanel(shelfId: shelfId, title: title),
  );
  if (wide) {
    return showDialog<void>(
      context: context,
      animationStyle: Motion.dialog(context),
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: body(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: Motion.sheet(context),
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
        child: body(context),
      ),
    ),
  );
}
