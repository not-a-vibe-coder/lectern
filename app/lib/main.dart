import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app.dart';
import 'src/platform/browser.dart';
import 'src/services/api.dart';

void main() {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final browser = createBrowserBridge();
  final api = LecternApi(baseUrl: Uri.parse(browser.origin));
  runApp(LecternBootstrap(browser: browser, api: api));
}
