import '../models/models.dart';
import '../platform/browser.dart';

/// Remembers when this browser last opened each shelf, to mark new items.
///
/// Times come from the server (`serverTime`), so a wrong phone clock cannot
/// hide new items. The baseline is pinned for the browser session: reloading
/// the page keeps the same items marked as new until the tab is closed.
class VisitTracker {
  VisitTracker({required this.local, required this.session});

  final KeyValueStore local;
  final KeyValueStore session;

  static String _lastKey(String shelfId) => 'lectern.lastVisit.$shelfId';
  static String _baselineKey(String shelfId) => 'lectern.baseline.$shelfId';

  /// Starts (or continues) a visit and returns the baseline: items added
  /// after it are new. Null on the first visit, when nothing is marked.
  DateTime? beginVisit(String shelfId, DateTime serverNow) {
    final pinned = session.get(_baselineKey(shelfId));
    final last = local.get(_lastKey(shelfId));
    local.set(_lastKey(shelfId), serverNow.toUtc().toIso8601String());
    if (pinned != null) {
      return pinned == 'none' ? null : DateTime.tryParse(pinned);
    }
    session.set(_baselineKey(shelfId), last ?? 'none');
    return last == null ? null : DateTime.tryParse(last);
  }

  /// Clears the new markers for this shelf.
  void markAllSeen(String shelfId, DateTime serverNow) {
    final stamp = serverNow.toUtc().toIso8601String();
    local.set(_lastKey(shelfId), stamp);
    session.set(_baselineKey(shelfId), stamp);
  }

  static bool isNew(Item item, DateTime? baseline) =>
      baseline != null && item.createdAt.isAfter(baseline);
}
