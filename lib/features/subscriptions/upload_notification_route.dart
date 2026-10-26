import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../innertube/models.dart';
import '../../providers.dart';
import '../../ui/navigation.dart';

class UploadNotificationVideoRoute extends ConsumerStatefulWidget {
  const UploadNotificationVideoRoute({required this.videoId, super.key});
  final String videoId;

  @override
  ConsumerState<UploadNotificationVideoRoute> createState() => _UploadNotificationVideoRouteState();
}

class _UploadNotificationVideoRouteState extends ConsumerState<UploadNotificationVideoRoute> {
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final info = await ref.read(videoInfoServiceProvider).get(widget.videoId);
      if (!mounted) return;
      final video = VideoItem(
        id: info.videoId,
        title: info.title,
        channelId: info.channelId,
        channelName: info.channelName,
        channelAvatar: info.channelAvatar,
        isShort: info.isShort,
        isLive: info.isLive,
        thumbnail: 'https://i.ytimg.com/vi/${info.videoId}/hqdefault.jpg',
      );
      playVideo(context, ref, video);
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nouvelle vidéo')),
    body: Center(
      child: _error == null
          ? const CircularProgressIndicator()
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Impossible de lancer cette vidéo dans YouPipe.'),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: () => context.go('/home'), child: const Text('Retour à l’accueil')),
                ],
              ),
            ),
    ),
  );
}
