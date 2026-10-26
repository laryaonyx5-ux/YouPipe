import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'db/app_database.dart';
import 'library_repository.dart';
import 'subscriptions_feed.dart';
import '../innertube/models.dart';

const uploadNotificationTask = 'youpipe.checkSubscribedUploads';
const _enabledKey = 'uploadNotificationsEnabled';
const _seenKey = 'uploadNotificationSeenIds';
const _mutedKey = 'uploadNotificationMutedChannels';

final uploadNotifications = UploadNotificationService();

@pragma('vm:entry-point')
void uploadNotificationBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != uploadNotificationTask) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_enabledKey) ?? true)) return true;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      final db = AppDatabase();
      await UploadNotificationService.checkUploads(db, prefs, plugin);
      await db.close();
      return true;
    } catch (e) {
      debugPrint('YouPipe upload notifications background check failed: $e');
      return false;
    }
  });
}

class UploadNotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        UploadNotificationService.pendingVideo = VideoItem.fromJson({
          'id': data['id'], 'title': data['title'], 'channelId': data['channelId'],
          'channelName': data['channelName'], 'thumbnail': data['thumbnail'],
        });
        final pending = UploadNotificationService.pendingVideo;
        if (pending != null && UploadNotificationService.onOpenVideo != null) {
          UploadNotificationService.pendingVideo = null;
          UploadNotificationService.onOpenVideo!(pending);
        }
      }
      _initialized = true;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'youpipe_uploads',
      'Nouvelles vidéos',
      description: 'Nouvelles vidéos des chaînes auxquelles vous êtes abonné',
      importance: Importance.high,
    ));
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? true)) return;
    await android?.requestNotificationsPermission();
    await Workmanager().initialize(uploadNotificationBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      'youpipe-upload-notification-check',
      uploadNotificationTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    // Establish the initial baseline now instead of waiting for the first periodic run.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) ?? true) {
      final db = AppDatabase();
      await checkUploads(db, prefs, _plugin);
      await db.close();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await initialize();
      // The first check records the current feed, avoiding a burst of old uploads.
      final db = AppDatabase();
      await checkUploads(db, prefs, _plugin);
      await db.close();
    } else {
      await Workmanager().cancelByUniqueName('youpipe-upload-notification-check');
    }
  }

  static Future<void> checkUploads(
    AppDatabase db,
    SharedPreferences prefs,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final subscriptions = await db.select(db.subscriptions).get();
    if (subscriptions.isEmpty) return;
    final muted = prefs.getStringList(_mutedKey)?.toSet() ?? <String>{};
    final seen = prefs.getStringList(_seenKey)?.toSet() ?? <String>{};
    final hadBaseline = prefs.containsKey(_seenKey);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final current = <String>{};
    final newRows = <({String id, String channelId, String channelName, String title, String? thumbnail, DateTime publishedAt})>[];
    for (final sub in subscriptions) {
      try {
        final response = await dio.get<String>(
          'https://www.youtube.com/feeds/videos.xml',
          queryParameters: {'channel_id': sub.channelId},
          options: Options(responseType: ResponseType.plain),
        );
        for (final entry in parseRss(response.data ?? '', channelId: sub.channelId, channelName: sub.name)) {
          final id = entry.videoId.value;
          current.add(id);
          if (hadBaseline && !seen.contains(id) && !muted.contains(sub.channelId) && entry.publishedAt.value.isAfter(DateTime.now().subtract(const Duration(hours: 24)))) {
            newRows.add((
              id: id,
              channelId: sub.channelId,
              channelName: entry.channelName.value,
              title: entry.title.value,
              thumbnail: entry.thumbnail.present ? entry.thumbnail.value : null,
              publishedAt: entry.publishedAt.value,
            ));
          }
        }
      } catch (e) {
        debugPrint('YouPipe: notification feed failed for ${sub.channelId}: $e');
      }
    }
    if (!hadBaseline) {
      await prefs.setStringList(_seenKey, current.toList());
      return;
    }
    newRows.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    for (final video in newRows.take(10)) {
      BigPictureStyleInformation? pictureStyle;
      try {
        final imageResponse = await dio.get<List<int>>(
          video.thumbnail ?? 'https://i.ytimg.com/vi/${video.id}/hqdefault.jpg',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)),
        );
        final imageBytes = Uint8List.fromList(imageResponse.data ?? const <int>[]);
        if (imageBytes.isNotEmpty) {
          pictureStyle = BigPictureStyleInformation(
            ByteArrayAndroidBitmap(imageBytes),
            contentTitle: video.channelName,
            summaryText: video.title,
          );
        }
      } catch (e) { debugPrint('YouPipe: notification thumbnail failed: $e'); }
      final details = AndroidNotificationDetails(
        'youpipe_uploads',
        'Nouvelles vidéos',
        channelDescription: 'Nouvelles vidéos des chaînes auxquelles vous êtes abonné',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: pictureStyle ?? BigTextStyleInformation(video.title, contentTitle: video.channelName),
        actions: const [
          AndroidNotificationAction('watch', 'Regarder', showsUserInterface: true),
          AndroidNotificationAction('watch_later', 'À regarder plus tard', showsUserInterface: false),
          AndroidNotificationAction('mute_channel', 'Désactiver les notifications', showsUserInterface: false),
        ],
      );
      await plugin.show(
        video.id.hashCode & 0x7fffffff,
        video.channelName,
        video.title,
        NotificationDetails(android: details),
        payload: jsonEncode({
          'id': video.id,
          'title': video.title,
          'channelId': video.channelId,
          'channelName': video.channelName,
          'thumbnail': video.thumbnail,
        }),
      );
    }
    final updatedSeen = {...seen, ...current}.toList();
    await prefs.setStringList(_seenKey, updatedSeen.length > 3000 ? updatedSeen.sublist(updatedSeen.length - 3000) : updatedSeen);
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    if (response.actionId == 'watch_later') {
      _saveWatchLater(payload);
      return;
    }
    if (response.actionId == 'mute_channel') {
      _muteChannel(payload);
      return;
    }
    final data = jsonDecode(payload) as Map<String, dynamic>;
    UploadNotificationService.pendingVideo = VideoItem.fromJson({
      'id': data['id'],
      'title': data['title'],
      'channelId': data['channelId'],
      'channelName': data['channelName'],
      'thumbnail': data['thumbnail'],
    });
    UploadNotificationService.onOpenVideo?.call(UploadNotificationService.pendingVideo!);
  }

  static VideoItem? pendingVideo;
  static void Function(VideoItem video)? onOpenVideo;

  Future<void> _saveWatchLater(String payload) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final video = _videoFromPayload(data);
    final db = AppDatabase();
    final library = LibraryRepository(db);
    final playlistId = await library.watchLaterId();
    await library.addToPlaylist(playlistId, video);
    await db.close();
  }

  Future<void> _muteChannel(String payload) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final channelId = data['channelId'] as String?;
    if (channelId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final muted = prefs.getStringList(_mutedKey)?.toSet() ?? <String>{};
    muted.add(channelId);
    await prefs.setStringList(_mutedKey, muted.toList());
  }

  static VideoItem _videoFromPayload(Map<String, dynamic> data) => VideoItem(
    id: data['id'] as String,
    title: data['title'] as String? ?? '',
    channelId: data['channelId'] as String?,
    channelName: data['channelName'] as String?,
    thumbnail: data['thumbnail'] as String?,
  );
}
