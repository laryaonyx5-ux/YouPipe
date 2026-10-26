import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/upload_notifications.dart';

Widget uploadNotificationSettings(BuildContext context, WidgetRef ref) => StatefulBuilder(
  builder: (context, setState) => FutureBuilder<bool>(
    future: SharedPreferences.getInstance().then((p) => p.getBool('uploadNotificationsEnabled') ?? true),
    builder: (context, snapshot) => SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: const Text('Notifications des nouvelles vidéos'),
      subtitle: const Text('Alerter quand une chaîne suivie publie une vidéo, avec des actions dans la notification.'),
      value: snapshot.data ?? true,
      onChanged: snapshot.connectionState == ConnectionState.waiting
          ? null
          : (value) async {
              await uploadNotifications.setEnabled(value);
              if (context.mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(value ? 'Notifications activées' : 'Notifications désactivées')),
                );
              }
            },
    ),
  ),
);
