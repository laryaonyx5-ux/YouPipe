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
                SliverToBoxAdapter(child: _Header(page: p)),
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

class _Header extends ConsumerWidget {
  const _Header({required this.page});

  final ChannelPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.yt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.banner != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AspectRatio(aspectRatio: 6.2, child: YtImage(page.banner, radius: 12)),
            ),
          Row(
            children: [
              Avatar(page.avatar, size: 72, name: page.name),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    if (page.handle != null)
                      Text(page.handle!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      page.metadata.join(' · '),
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (page.description?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                builder: (_) => DraggableScrollableSheet(
                  expand: false,
                  builder: (_, scroll) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      const Text('À propos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      HtmlText(page.description!, style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      page.description!.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                  ),
                  Icon(Symbols.chevron_right, color: c.textSecondary),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: SubscribeButton(page.asItem)),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliiverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.color);

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: color, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar || old.color != color;
}

class _TabContent extends ConsumerStatefulWidget {
  const _TabContent({required this.channelId, required this.tab, this.initial});

  final String channelId;
  final ChannelTab tab;
  final ChannelPage? initial;

  @override
  ConsumerState<_TabContent> createState() => _TabContentState();
}

class _TabContentState extends ConsumerState<_TabContent> with AutomaticKeepAliveClientMixin {
  String? _sortToken;
  String _sortLabel = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final params = widget.tab.selected ? null : widget.tab.params;
    final tabPage = ref.watch(channelProvider((channelId: widget.channelId, params: params)));
    final key = (channelId: widget.channelId, params: params, sortToken: _sortToken);
    final list = ref.watch(channelListProvider(key));
    final entries = list.value?.items ?? const <FeedEntry>[];
    final chips = tabPage.value?.sortChips ?? const <SortChip>[];
    final isShorts = widget.tab.title == 'Shorts';
    final items = entries.allItems.toList();

    Widget body;
    if (list.isLoading && entries.isEmpty) {
      body = const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(32), child: LoadingView()),
      );
    } else if (list.hasError && entries.isEmpty) {
      body = SliverToBoxAdapter(
        child: ErrorView(error: list.error!, compact: true, onRetry: () => ref.invalidate(channelListProvider(key))),
      );
    } else if (entries.isEmpty) {
      body = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Cette chaîne ne contient aucun élément dans la section ${widget.tab.title.toLowerCase()}',
              style: TextStyle(color: context.yt.textSecondary),
            ),
          ),
        ),
      );
    } else if (isShorts) {
      body = SliverPadding(
        padding: const EdgeInsets.all(4),
        sliver: SliverGrid.builder(
          // 3 across on phones, more on tablets and TVs.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 9 / 16,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => switch (items[i]) {
            final VideoItem v => LayoutBuilder(builder: (context, box) => ShortCard(v, width: box.maxWidth)),
            _ => const SizedBox.shrink(),
          },
        ),
      );
    } else {
      body = FeedSliver(entries);
    }

    return LoadMoreListener(
      onLoadMore: () => ref.read(channelListProvider(key).notifier).loadMore(),
      child: CustomScrollView(
        key: PageStorageKey(widget.tab.title),
        slivers: [
          if (chips.isNotEmpty)
            SliverToBoxAdapter(
              child: ChipBar(
                children: [
                  for (final c in chips)
                    YtChip(
                      label: c.label,
                      selected: _sortLabel.isEmpty ? c.selected : c.label == _sortLabel,
                      onTap: () => setState(() {
                        _sortLabel = c.label;
                        _sortToken = c.selected ? null : c.token;
                      }),
                    ),
                ],
              ),
            ),
          body,
          if (list.value?.loadingMore ?? false)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(24), child: LoadingView()),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverBottomInset(),
        ],
      ),
    );
  }
}


/// Native Community posts loaded from YouTube's InnerTube browse endpoint.
class _ChannelPostsTab extends ConsumerStatefulWidget {
  const _ChannelPostsTab({required this.channelId, required this.tab});

  final String channelId;
  final ChannelTab tab;

  @override
  ConsumerState<_ChannelPostsTab> createState() => _ChannelPostsTabState();
}

class _ChannelPostsTabState extends ConsumerState<_ChannelPostsTab> {
  final ScrollController _scroll = ScrollController();
  final List<CommunityPost> _posts = [];
  String? _continuation;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _loadFirst();
  }

  @override
  void didUpdateWidget(covariant _ChannelPostsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId || oldWidget.tab.params != widget.tab.params) {
      _posts.clear();
      _continuation = null;
      _error = null;
      _hasLoaded = false;
      _loading = true;
      _loadFirst();
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    if (_hasLoaded) return;
    _hasLoaded = true;
    try {
      final page = await ref.read(innerTubeProvider).channelPosts(
        widget.channelId,
        params: widget.tab.params ?? '',
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _continuation = page.continuation;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 600 || _loadingMore || _continuation == null) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final token = _continuation;
    if (token == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(innerTubeProvider).channelPostsContinuation(token);
      if (!mounted) return;
      setState(() {
        final known = _posts.map((p) => p.id).toSet();
        _posts.addAll(page.posts.where((p) => known.add(p.id)));
        _continuation = page.continuation == token ? null : page.continuation;
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
      );
    }
    if (_error != null && _posts.isEmpty) {
      return CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Impossible de charger les publications.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () { _hasLoaded = false; setState(() => _loading = true); _loadFirst(); }, child: const Text('Réessayer')),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_posts.isEmpty) {
      return CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Aucune publication trouvée.')))],
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _hasLoaded = false;
        setState(() {
          _loading = true;
          _error = null;
          _continuation = null;
          _posts.clear();
        });
        await _loadFirst();
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliiverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _CommunityPostCard(post: _posts[index]),
                childCount: _posts.length,
              ),
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))),
          if (_error != null)
            SliverToBoxAdapter(
              child: Center(
                child: TextButton(onPressed: _loadMore, child: const Text('Erreur de chargement — réessayer')),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverBottomInset(),
        ],
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.yt;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: c.raised,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(post.authorAvatar, size: 40, name: post.author),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.author ?? 'Publication', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                      if (post.publishedText != null)
                        Text(post.publishedText!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            if (post.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(post.text, style: TextStyle(color: c.textPrimary, height: 1.35)),
            ],
            for (final url in post.images)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, box) => YtImage(url, width: box.maxWidth, fit: BoxFit.contain),
                  ),
                ),
              ),
            if (post.pollOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final option in post.pollOptions)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(option, style: TextStyle(color: c.textPrimary)),
                ),
            ],
            if (post.likeCount != null || post.commentCount != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (post.likeCount != null) ...[
                    Icon(Symbols.thumb_up, size: 17, color: c.textSecondary),
                    const SizedBox(width: 4),
                    Text(post.likeCount!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                    const SizedBox(width: 16),
                  ],
                  if (post.commentCount != null) ...[
                    Icon(Symbols.mode_comment, size: 17, color: c.textSecondary),
                    const SizedBox(width: 4),
                    Text(post.commentCount!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Fallback for channels whose native community feed is incomplete.
/// Keep YouTube's community page inside this tab, while hiding its own bottom
/// navigation and subscription controls so the app's navigation stays in charge.
class _ChannelPostsWebTab extends StatefulWidget {
  const _ChannelPostsWebTab({required this.channelId});

  final String channelId;

  @override
  State<_ChannelPostsWebTab> createState() => _ChannelPostsWebTabState();
}

class _ChannelPostsWebTabState extends State<_ChannelPostsWebTab> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F0F0F))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            await _controller.runJavaScript('''
              (() => {
                const styleId = 'youpipe-community-cleanup';
                let style = document.getElementById(styleId);
                if (!style) {
                  style = document.createElement('style');
                  style.id = styleId;
                  document.head.appendChild(style);
                }
                style.textContent = `
                  ytm-pivot-bar-renderer,
                  .pivot-bar-renderer,
                  ytd-mini-guide-renderer,
                  ytd-guide-renderer,
                  tp-yt-app-drawer,
                  #guide-button,
                  ytm-subscribe-button-renderer,
                  ytd-subscribe-button-renderer,
                  ytm-slim-owner-renderer .subscribe-button,
                  ytm-channel-header-renderer .subscribe-button,
                  button[aria-label="Subscribe"],
                  button[aria-label="S’abonner"],
                  a[aria-label="Subscribe"],
                  a[aria-label="S’abonner"] {
                    display: none !important;
                    visibility: hidden !important;
                    height: 0 !important;
                    min-height: 0 !important;
                  }
                  html, body { overflow-y: auto !important; }
                `;
                document.documentElement.style.overflowY = 'auto';
                document.body.style.overflowY = 'auto';
              })();
            ''');
            if (mounted) setState(() { _loading = false; _error = null; });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() { _loading = false; _error = error.description; });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.youtube.com/channel/${widget.channelId}/community'));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impossible d’ouvrir les publications YouTube.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() { _loading = true; _error = null; });
                  _controller.loadRequest(Uri.parse('https://www.youtube.com/channel/${widget.channelId}/community'));
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF0F0F0F),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
