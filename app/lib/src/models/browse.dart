import 'models.dart';

/// What the student is looking for on a shelf.
class BrowseFilter {
  const BrowseFilter({this.query = '', this.type, this.onlyNew = false});

  final String query;
  final ItemType? type;
  final bool onlyNew;

  bool get isActive => query.trim().isNotEmpty || type != null || onlyNew;

  BrowseFilter copyWith({
    String? query,
    ItemType? type,
    bool clearType = false,
    bool? onlyNew,
  }) => BrowseFilter(
    query: query ?? this.query,
    type: clearType ? null : (type ?? this.type),
    onlyNew: onlyNew ?? this.onlyNew,
  );
}

class CourseGroup {
  const CourseGroup(this.courseCode, this.items);
  final String courseCode;
  final List<Item> items;
}

String _squash(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// True when [item] matches the search text, by title or course code.
/// "csc301", "CSC 301" and "csc 3" all match "CSC 301".
bool matchesQuery(Item item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (item.title.toLowerCase().contains(q)) return true;
  return _squash(item.courseCode).contains(_squash(q));
}

/// Filters items and groups them by course code. Groups are sorted by code;
/// inside a group, lecture notes come first, then past questions,
/// assignments and other files, each sorted by title.
List<CourseGroup> groupItems(
  List<Item> items, {
  BrowseFilter filter = const BrowseFilter(),
  DateTime? baseline,
}) {
  final groups = <String, List<Item>>{};
  for (final item in items) {
    if (filter.type != null && item.type != filter.type) continue;
    if (filter.onlyNew &&
        !(baseline != null && item.createdAt.isAfter(baseline))) {
      continue;
    }
    if (!matchesQuery(item, filter.query)) continue;
    groups.putIfAbsent(item.courseCode, () => []).add(item);
  }
  final codes = groups.keys.toList()..sort(_compareCodes);
  return [
    for (final code in codes)
      CourseGroup(code, groups[code]!..sort(_compareItems)),
  ];
}

int _compareCodes(String a, String b) => a.compareTo(b);

int _compareItems(Item a, Item b) {
  final byType = a.type.index.compareTo(b.type.index);
  if (byType != 0) return byType;
  return _naturalCompare(a.title.toLowerCase(), b.title.toLowerCase());
}

/// Compares strings so that "week 2" sorts before "week 10".
int _naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final c = na != null && nb != null
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

Map<ItemType, int> countByType(Iterable<Item> items) {
  final counts = {for (final t in ItemType.values) t: 0};
  for (final item in items) {
    counts[item.type] = counts[item.type]! + 1;
  }
  return counts;
}

int countNew(Iterable<Item> items, DateTime? baseline) => baseline == null
    ? 0
    : items.where((i) => i.createdAt.isAfter(baseline)).length;
