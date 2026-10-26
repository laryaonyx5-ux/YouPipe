import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/theme/yt_theme.dart';

/// Native inbox for notifications detected by YouPipe. It never opens a browser.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _historyKey = 'uploadNotificationHistory';
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = <Map<String, dynamic>>[];
    for (final raw in prefs.getStringList(_historyKey) ?? const <String>[]) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) rows.add(decoded);
      } catch (_) {
        // Ignore old/corrupt entries without preventing the inbox from opening.
      }
    }
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.yt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Symbols.arrow_back)),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Symbols.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.notifications_none, size: 52, color: c.textSecondary),
                        const SizedBox(height: 12),
                        Text('Aucune notification pour le moment', style: TextStyle(color: c.textPrimary, fontSize: 17)),
                        const SizedBox(height: 8),
                        Text(
                          'Les nouvelles vidéos détectées sur tes chaînes suivies apparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final id = item['id'] as String? ?? '';
                      final title = item['title'] as String? ?? 'Nouvelle vidéo';
                      final channel = item['channelName'] as String? ?? 'YouTube';
                      final thumbnail = item['thumbnail'] as String?;
                      final published = item['publishedAt'] as String?;
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 104,
                            height: 58,
                            child: thumbnail == null
                                ? ColoredBox(color: c.chip, child: Icon(Symbols.play_circle, color: c.textSecondary))
                                : Image.network(
                                    thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: c.chip,
                                      child: Icon(Symbols.play_circle, color: c.textSecondary),
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(channel, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '$title${published == null ? '' : '\n$published'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        onTap: id.isEmpty ? null : () => context.push('/notification-video/$id'),
                      );
                    },
                  ),
                ),
    );
  }
}
