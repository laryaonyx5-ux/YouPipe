import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/subscriptions_feed.dart';
import '../../innertube/innertube.dart';
import '../account/account.dart';
import '../../innertube/models.dart';
import '../../providers.dart';
import '../../ui/navigation.dart';
import '../../ui/theme/yt_theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/top_bar.dart';
import '../../ui/widgets/video_tiles.dart';

enum _Filter { all, today, videos, shorts, continueWatching, unwatched }

const _labels = {
  _Filter.all: 'Tout',
  _Filter.today: "Aujourd'hui",
  _Filter.videos: 'Vidéos',
  _Filter.shorts: 'Shorts',
  _Filter.continueWatching: 'Reprendre la lecture',
  _Filter.unwatched: 'Non regardées',
};

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_syncYouTubeSubscriptions().catchError((Object e) {
      debugPrint('YouPipe: subscription import failed: $e');
    }));
    ref.read(subscriptionsFeedServiceProvider).refresh();
  }

  /// Retry importing the signed-in YouTube account whenever this tab is opened or refreshed.
  Future<void> _syncYouTubeSubscriptions() async {
    await ref.read(authProvider.future);
    final yt = ref.read(innerTubeProvider);
    if (!yt.signedIn) return;

    var page = await yt.subscribedChannels();
    final channels = <String, ChannelItem>{
      for (final channel in page.entries.allItems.whereType<ChannelItem>()) channel.id: channel,
    };
    final seenContinuations = <String>{};
    var pageCount = 0;
    while (page.continuation != null && channels.length < 5000 && pageCount < 100) {
      final continuation = page.continuation!;
      if (!seenContinuations.add(continuation)) {
        debugPrint('YouPipe: stopped repeated subscription continuation');
        break;
      }
      pageCount++;
      page = await yt.browseContinuation(continuation);
      final more = page.entries.allItems.whereType<ChannelItem>();
      if (more.isEmpty) break;
      for (final channel in more) {
        channels[channel.id] = channel;
      }
    }
    if (channels.isEmpty) {
      debugPrint('YouPipe: YouTube returned no subscription channels to import');
      return;
    }
    final added = await ref.read(libraryProvider).importSubscriptions(channels.values.toList());
    debugPrint('YouPipe: imported ${channels.length} YouTube subscriptions ($added import attempts)');
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider).value ?? const <ChannelItem>[];
    final feed = ref.watch(subscriptionFeedProvider);
    final progress = ref.watch(watchProgressProvider).value ?? const <String, double>{};
    final all = feed.value ?? const <FeedVideo>[];
    final now = DateTime.now();
    final filtered = [
      for (final f in all)
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.today => now.difference(f.publishedAt).inHours < 24,
          _Filter.videos => !f.video.isShort,
          _Filter.shorts => f.video.isShort,
          _Filter.continueWatching => (progress[f.video.id] ?? 0) > 0 && (progress[f.video.id] ?? 0) < 0.9,
          _Filter.unwatched => !progress.containsKey(f.video.id),
        })
          f.video,
    ];
    final videos = filtered.where((v) => !v.isShort || _filter == _Filter.shorts).toList();
    final shorts = _filter == _Filter.all ? filtered.where((v) => v.isShort).take(12).toList() : const <VideoItem>[];

    return Scaffold(
      body: StatusBarScrim(
        child: RefreshIndicator(
          color: context.yt.textPrimary,
          onRefresh: () async {
            await _syncYouTubeSubscriptions();
            await ref.read(subscriptionsFeedServiceProvider).refresh(force: true);
          },
          child: CustomScrollView(
            slivers: [
              const YtTopBar(),
              if (subs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Symbols.subscriptions,
                    title: "Ne manquez aucune nouvelle vidéo",
                    message:
                        'Abonnez-vous à des chaînes pour voir leurs dernières vidéos ici. Vos abonnements sont conservés sur cet appareil.',
                    action: FilledButton(onPressed: () => openSearch(context, ref), child: const Text('Trouver des chaînes')),
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: _ChannelStrip(channels: subs)),
                SliverToBoxAdapter(
                  child: ChipBar(
                    children: [
                      for (final f in _Filter.values)
                        YtChip(label: _labels[f]!, selected: f == _filter, onTap: () => setState(() => _filter = f)),
                    ],
                  ),
                ),
                if (feed.isLoading && all.isEmpty)
                  const SliverToBoxAdapter(child: FeedSkeleton())
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyView(
                      icon: Symbols.video_library,
                      title: all.isEmpty ? 'Chargement de vos abonnements…' : 'Rien à afficher',
                      message: all.isEmpty ? 'Tirez vers le bas pour actualiser.' : 'Essayez un autre filtre.',
                    ),
                  )
                else if (_filter == _Filter.shorts)
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid.builder(
                      // 2 across on phones, more on tablets and TVs.
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 9 / 16,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: videos.length,
                      itemBuilder: (_, i) =>
                          LayoutBuilder(builder: (_, box) => ShortCard(videos[i], width: box.maxWidth)),
                    ),
                  )
                else
                  VideosWithShortsSliver(videos: videos, shorts: shorts, phoneShelfAt: 1),
              ],
              const SliverBottomInset(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row of channel avatars with "Tout" at the end.
class _ChannelStrip extends ConsumerWidget {
  const _ChannelStrip({required this.channels});

  final List<ChannelItem> channels;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    height: 96,
    child: Row(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: channels.length,
            itemBuilder: (_, i) => InkWell(
              onTap: () => openChannel(context, ref, channels[i].id),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Avatar(channels[i].avatar, size: 56, name: channels[i].name),
                    const SizedBox(height: 6),
                    Text(
                      channels[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: context.yt.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.push('${branchPrefix(context)}/channels'),
          style: TextButton.styleFrom(foregroundColor: context.yt.link),
          child: const Text('Tout', style: TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

/// All subscriptions, A–Z. Import the signed-in account again when this screen opens.
class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  static final extraActions = <Widget Function(BuildContext, WidgetRef)>[];

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  bool _syncing = true;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshChannels());
  }

  Future<void> _refreshChannels() async {
    try {
      await ref.read(authProvider.future);
      final yt = ref.read(innerTubeProvider);
      if (yt.signedIn) {
        var page = await yt.subscribedChannels();
        final channels = <String, ChannelItem>{
          for (final channel in page.entries.allItems.whereType<ChannelItem>()) channel.id: channel,
        };
        while (page.continuation != null && channels.length < 5000) {
          page = await yt.browseContinuation(page.continuation!);
          final more = page.entries.allItems.whereType<ChannelItem>();
          if (more.isEmpty) break;
          for (final channel in more) {
            channels[channel.id] = channel;
          }
        }
        if (channels.isNotEmpty) {
          await ref.read(libraryProvider).importSubscriptions(channels.values.toList());
        }
      }
      // Do not block this channel list on downloading every channel's video feed.
    } catch (e) {
      _syncError = e.toString();
      debugPrint('YouPipe: unable to refresh all subscriptions: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider).value ?? const <ChannelItem>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tous les abonnements'),
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Symbols.arrow_back)),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _syncing ? null : () => setState(() {
              _syncing = true;
              _syncError = null;
              unawaited(_refreshChannels());
            }),
            icon: const Icon(Symbols.refresh),
          ),
          for (final a in ChannelsScreen.extraActions) a(context, ref),
        ],
      ),
      body: MaxContentWidth(
        child: _syncing && subs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : subs.isEmpty
                ? EmptyView(
                    icon: Symbols.subscriptions,
                    title: 'Aucun abonnement trouvé',
                    message: _syncError == null
                        ? 'Connecte-toi à ton compte YouTube ou recherche des chaînes pour les ajouter.'
                        : 'Impossible de charger les abonnements. Vérifie ta connexion puis actualise.',
                  )
                : RefreshIndicator(
                    onRefresh: _refreshChannels,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: subs.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: Avatar(subs[i].avatar, size: 48, name: subs[i].name),
                        title: Text(subs[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => openChannel(context, ref, subs[i].id),
                        trailing: SubscribeButton(subs[i], compact: true),
                      ),
                    ),
                  ),
      ),
    );
  }
}
