/// Separates historical records from events arriving while the listener starts.
/// Cache and pending writes never consume an event's server-confirmed version.
class BannerEventCursor {
  BannerEventCursor(this.startedAt);
  final DateTime startedAt;
  final Map<String, DateTime> _versions = {};

  bool accept(
    String id,
    DateTime at, {
    required bool fromCache,
    required bool pendingWrites,
    required bool firstServerSnapshot,
  }) {
    if (fromCache || pendingWrites || _versions[id] == at) return false;
    _versions[id] = at;
    if (_versions.length > 3000) _versions.remove(_versions.keys.first);
    // Keep historical notifications in their lists, while preserving genuinely
    // new records that arrived during the initial server round trip.
    return !firstServerSnapshot || !at.isBefore(startedAt);
  }
}
