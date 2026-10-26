import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../innertube/models.dart';
import '../../providers.dart';
import '../../ui/theme/yt_theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/html_text.dart';
import '../../ui/widgets/video_tiles.dart';

/// Supported channel tabs in English and French, following YouTube's language setting.
const _supportedTabs = {'Home', 'Accueil', 'Videos', 'Vidéos', 'Shorts', 'Live', 'En direct', 'Diffusions en direct', 'Releases', 'Sorties', 'Playlists', 'Podcasts', 'Posts', 'Publications', 'Communauté'};

class ChannelScreen extends ConsumerWidget {
  const ChannelScreen({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(channelProvider((channelId: channelId, params: null)));
    return page.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: e, onRetry: () => ref.invalidate(channelProvider((channelId: channelId, params: null)))),
      ),
      data: (p) {
        // Keep the channel's name and picture fresh in Subscriptions.
        ref.read(libraryProvider).refreshSubscription(p.asItem);
        final supportedTabs = p.tabs.where((t) => _supportedTabs.contains(t.title)).toList();
        // Never create a zero-tab controller: some YouTube locales use labels we do not recognize yet.
        final tabs = supportedTabs.isNotEmpty
            ? supportedTabs
            : (p.tabs.isNotEmpty ? p.tabs.take(1).toList() : const [ChannelTab('Vidéos', null, selected: true)]);
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  pinned: true,
                  title: Text(p.name),
                  leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Symbols.arrow_back)),
                  actions: [
                    IconButton(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(text: 'https://www.youtube.com/${p.handle ?? 'channel/${p.id}'}'),
                      ),
                      icon: const Icon(Symbols.share, weight: 300),
                    ),
                  ],
                ),
                SliiverToBoxAdapter(child: _Header(page: p)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.title)]),
                    context.yt.background,
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  for (final t in tabs)
                    if (['posts', 'publications', 'communauté'].contains(t.title.toLowerCase()))
                      _ChannelPostsTab(channelId: channelId, tab: t)
                    else
                      _TabContent(channelId: channelId, tab: t, initial: t.selected ? p : null),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
