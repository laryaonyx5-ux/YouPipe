/// Feature registration: later phases (downloads, sign-in, SponsorBlock, cast, updates) plug their routes, menu
/// entries, settings sections and startup providers in here, so the core screens don't import them directly.
library;

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter/material.dart' show Colors;
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'features/account/account.dart';
import 'features/cast/cast_feature.dart';
import 'features/downloads/downloads.dart';
import 'features/remote_config.dart';
import 'features/settings/settings_screen.dart';
import 'features/sponsorblock/sponsorblock.dart';
import 'features/subscriptions/import_export.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/subscriptions/upload_notification_route.dart';
import 'features/subscriptions/upload_notification_settings.dart';
import 'features/update/update.dart';
import 'features/watch/player_view.dart';
import 'features/watch/seek_bar.dart';
import 'features/you/you_screen.dart';
import 'providers.dart';
import 'ui/router.dart';
import 'ui/shell/app_shell.dart';
import 'ui/widgets/top_bar.dart';
import 'ui/widgets/video_menu.dart';
import 'ui/layout.dart';

final rootProviders = <ProviderListenable<Object?>>[];

void registerFeatures() {
  rootProviders.add(remoteConfigProvider);

  rootProviders.add(sbSkipperProvider);
  seekBarSegments = sbSeekBarSegments;
  settingsExtraSections.add(sponsorBlockSettings);

  rootProviders.add(downloadManagerProvider);
  downloadStarter = startDownload;
  downloadPillBuilder = downloadPill;
  extraDetailRoutes.add(() => GoRoute(path: 'downloads', builder: (_, _) => const DownloadsScreen()));
  youExtraEntries.add((icon: Symbols.download, label: 'Downloads', onTap: openDownloads));

  rootProviders.add(authProvider);
  youHeaderBuilder = accountHeader;
  extraRootRoutes.add(
    GoRoute(path: '/login', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const LoginScreen()),
  );
  extraDetailRoutes.add(
    () => GoRoute(
      path: 'account/:id',
      builder: (_, s) =>
          AccountFeedScreen(browseId: s.pathParameters['id']!, title: s.uri.queryParameters['title'] ?? ''),
    ),
  );

  // Notifications from subscribed channels, with internal video opening.
  extraRootRoutes.add(
    GoRoute(
      path: '/notification-video/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, s) => UploadNotificationVideoRoute(videoId: s.pathParameters['id']!),
    ),
  );
  settingsExtraSections.add(uploadNotificationSettings);

  if (!DeviceInfo.current.tv) {
    rootProviders.add(castBridgeProvider);
    remoteControlsOf = castRemoteOf;
    castingViewBuilder = castingView;
    playerCastButton = () => const CastButton(color: Colors.white);
    topBarExtraActions.add((_) => const CastButton());
  }

  shellStartHooks.add(checkForUpdateOnLaunch);
  settingsExtraSections.add(updateSettings);
  ChannelsScreen.extraActions.add(subscriptionsMenu);
}
