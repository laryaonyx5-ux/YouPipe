import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers.dart';
import '../../ui/theme/yt_theme.dart';
import '../../ui/widgets/common.dart';

/// Extra settings sections registered by later features (SponsorBlock, downloads, account, updates).
final settingsExtraSections = <Widget Function(BuildContext, WidgetRef)>[];

const _languages = {
  'en": 'English",
  'hi': 'हिन्दी',
  'ml': 'മലയാളം',
  'ta': 'தமிழ்',
  'es": 'Espagnol",
  'fr": 'Français",
  'de": 'Deutsch",
  'pt": 'Portugais",
  'it": 'Italiano",
  'ja': '日本語',
  'ko': '한국어',
  'ar': 'العربية',
  'ru': 'Русский',
};

const _regions = {
  'US": 'États-Unis",
  'GB": 'Royaume-Uni",
  'IE": 'Ireland",
  'IN": 'India",
  'CA": 'Canada",
  'AU": 'Australia",
  'DE": 'Germany",
  'FR": 'France",
  'ES": 'Spain",
  'BR": 'Brazil",
  'JP": 'Japan",
  'KR": 'Corée du Sud",
  'AE": 'Émirats arabes unis",
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final c = context.yt;
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        t,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.textSecondary),
      ),
    );
    Future<T?> pick<T>(String title, Map<T, String> options, T selected) => showDialog<T>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          for (final e in options.entries)
            ChoiceTile(title: e.value, selected: e.key == selected, onTap: () => Navigator.pop(d, e.key)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Symbols.arrow_back)),
      ),
      body: MaxContentWidth(
        child: ListView(
          children: [
            header('General'),
            ListTile(
              title: const Text('Apparence'),
              subtitle: Text(switch (s.themeMode) {
                ThemeMode.system => "Utiliser le thème de l'appareil",
                ThemeMode.dark => 'Thème sombre',
                ThemeMode.light => 'Thème clair',
              }),
              onTap: () async {
                final m = await pick('Apparence', {
                  ThemeMode.system: "Utiliser le thème de l'appareil",
                  ThemeMode.dark: 'Thème sombre',
                  ThemeMode.light: 'Thème clair',
                }, s.themeMode);
                if (m != null) await ctl.update(s.copyWith(themeMode: m));
              },
            ),
            ListTile(
              title: const Text('Langue'),
              subtitle: Text(_languages[s.hl] ?? s.hl),
              onTap: () async {
                final v = await pick('Langue', _languages, s.hl);
                if (v != null) await ctl.update(s.copyWith(hl: v));
              },
            ),
            ListTile(
              title: const Text('Région'),
              subtitle: Text(_regions[s.gl] ?? s.gl),
              onTap: () async {
                final v = await pick('Région', _regions, s.gl);
                if (v != null) await ctl.update(s.copyWith(gl: v));
              },
            ),
            SwitchListTile(
              title: const Text("Image dans l'image"),
              subtitle: const Text("Continuer à regarder dans une petite fenêtre en quittant l'application"),
              value: s.pip,
              onChanged: (v) => ctl.update(s.copyWith(pip: v)),
            ),
            const Divider(),
            // Autoplay is switched in the player, like YouTube (docs/playback.md).
            header('Playback'),
            SwitchListTile(
              title: const Text('Reprendre là où vous en étiez'),
              value: s.resume,
              onChanged: (v) => ctl.update(s.copyWith(resume: v)),
            ),
            const Divider(),
            header('Préférences de qualité vidéo'),
            for (final q in VideoQualityPref.values)
              ChoiceTile(
                title: q.label,
                subtitle: q.description,
                selected: q == s.quality,
                onTap: () => ctl.update(s.copyWith(quality: q)),
              ),
            for (final section in settingsExtraSections) section(context, ref),
            const Divider(),
            header("Gérer tout l'historique"),
            SwitchListTile(
              title: const Text("Suspendre l'historique des vidéos regardées"),
              value: !s.saveHistory,
              onChanged: (v) => ctl.update(s.copyWith(saveHistory: !v)),
            ),
            SwitchListTile(
              title: const Text("Suspendre l'historique des recherches"),
              value: !s.saveSearchHistory,
              onChanged: (v) => ctl.update(s.copyWith(saveSearchHistory: !v)),
            ),
            ListTile(
              title: const Text("Effacer l'historique des vidéos regardées"),
              onTap: () async {
                await ref.read(libraryProvider).clearHistory();
                if (context.mounted) showSnack(context, 'Historique des vidéos regardées effacé');
              },
            ),
            ListTile(
              title: const Text("Effacer l'historique des recherches"),
              onTap: () async {
                await ref.read(libraryProvider).clearSearches();
                if (context.mounted) showSnack(context, 'Historique des recherches effacé');
              },
            ),
            const Divider(),
            header('About'),
            ListTile(
              title: const Text('Licences des logiciels libres'),
              onTap: () => showLicensePage(context: context, applicationName: 'YouPipe'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Text(
                'YouPipe is an independent, open-source app. It isn\'t made by or affiliated with YouTube or Google.',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
