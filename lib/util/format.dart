/// Number, duration and date formatting the way YouTube shows them.
library;

/// Translate common English relative ages returned by YouTube.
String localizeRelativeText(String text) {
  return text.replaceAllMapped(
    RegExp(r'\b(\d+)\s+(years?|months?|weeks?|days?|hours?|minutes?|seconds?)\s+ago\b', caseSensitive: false),
    (m) {
      final n = int.parse(m[1]!);
      final raw = m[2]!.toLowerCase();
      final unit = switch (raw) {
        'year' || 'years' => 'an',
        'month' || 'months' => 'mois',
        'week' || 'weeks' => 'semaine',
        'day' || 'days' => 'jour',
        'hour' || 'hours' => 'heure',
        'minute' || 'minutes' => 'minute',
        _ => 'seconde',
      };
      return 'il y a $n $unit${n == 1 || unit == 'mois' || unit == 'an' ? '' : 's'}';
    },
  ).replaceAll(RegExp(r'\bStreamed\b', caseSensitive: false), 'Diffusé')
   .replaceAll(RegExp(r'\bPremiered\b', caseSensitive: false), 'Première')
   .replaceAll(RegExp(r'\bScheduled\b', caseSensitive: false), 'Programmé');
}

/// Translate common English view-count labels returned by YouTube.
String localizeViewsText(String text) => text
    .replaceAll(RegExp(r'\bNo views\b', caseSensitive: false), 'Aucune vue')
    .replaceAll(RegExp(r'\bviews\b', caseSensitive: false), 'vues')
    .replaceAll(RegExp(r'\bview\b', caseSensitive: false), 'vue')
    .replaceAll(RegExp(r'\bwatching\b', caseSensitive: false), 'en direct');

/// "1.2M", "34K", "999". YouTube rounds down: 1,290,000 is "1.2M".
String compactCount(int n) {
  String fmt(double v, String unit) {
    if (v >= 10) return '${v.floor()}$unit';
    final one = (v * 10).floor() / 10;
    return '${one == one.roundToDouble() ? one.toInt() : one}$unit';
  }

  if (n >= 1000000000) return fmt(n / 1000000000, 'B');
  if (n >= 1000000) return fmt(n / 1000000, 'M');
  if (n >= 1000) return fmt(n / 1000, 'K');
  return '$n';
}

/// Libellé français du nombre de vues.
String viewsLabel(int n) => n < 0
    ? ''
    : n == 0
    ? 'Aucune vue'
    : n == 1
    ? '1 vue'
    : '${compactCount(n)} vues';

/// Affiche les dates relatives en français, comme « il y a 3 heures ».
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  String unit(int n, String u) => 'il y a $n $u${n == 1 || u == 'mois' ? '' : 's'}';
  if (d.inDays >= 365) return unit(d.inDays ~/ 365, 'an');
  if (d.inDays >= 30) return unit(d.inDays ~/ 30, 'mois');
  if (d.inDays >= 7) return unit(d.inDays ~/ 7, 'semaine');
  if (d.inDays >= 1) return unit(d.inDays, 'jour');
  if (d.inHours >= 1) return unit(d.inHours, 'heure');
  if (d.inMinutes >= 1) return unit(d.inMinutes, 'minute');
  return "À l'instant";
}

/// NewPipe's upload date ("2026-10-03T05:30:31-07:00") as "3 hours ago"; other text is returned as-is.
String? relativeDate(String? text) {
  if (text == null || text.isEmpty) return null;
  final t = DateTime.tryParse(text);
  return t == null ? text : timeAgo(t.toLocal());
}

/// "3:07", "1:02:03".
String formatDuration(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}${h > 0 ? '$h:$m:$s' : '$m:$s'}';
}
