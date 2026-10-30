import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../ui/navigation/destinations.dart';
import '../../ui/widgets/media_card.dart';
import '../models/subscription_models.dart';
import '../state/subscription_controller.dart';

class SubscriptionHomeScreen extends StatefulWidget {
  const SubscriptionHomeScreen({super.key});

  @override
  State<SubscriptionHomeScreen> createState() => _SubscriptionHomeScreenState();
}

class _SubscriptionHomeScreenState extends State<SubscriptionHomeScreen> {
  final _controller = SubscriptionController.instance;
  final _searchController = TextEditingController();

  SubscriptionSite? _site;
  VodCategory? _category;
  String? _repoId;
  String? _searchQuery;
  bool _searching = false;

  List<Vod> _items = const [];
  List<VodCategory> _categories = const [];
  int _page = 1;
  int _pageCount = 1;
  bool _loading = false;
  String? _error;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _controller.ensureLoaded();
    if (!mounted) return;
    _applyRepo(load: true);
  }

  void _onControllerChanged() {
    final repo = _controller.activeRepo;
    if (repo?.id != _repoId) {
      _applyRepo(load: true);
    } else if (mounted) {
      setState(() {});
    }
  }

  void _applyRepo({required bool load}) {
    final repo = _controller.activeRepo;
    final sites = repo?.sites.where((site) => site.isSupported).toList() ?? [];
    final site = sites.isNotEmpty ? sites.first : null;
    setState(() {
      _repoId = repo?.id;
      _site = site;
      _category = null;
      _searchQuery = null;
      _items = const [];
      _categories = const [];
      _page = 1;
      _pageCount = 1;
      _error = null;
    });
    if (load && site != null) {
      _load(reset: true);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final site = _site;
    final repo = _controller.activeRepo;
    if (site == null || repo == null) return;

    if (!reset && _page >= _pageCount) return;
    final nextPage = reset ? 1 : _page + 1;
    final token = ++_requestToken;

    setState(() {
      _loading = true;
      if (reset) _error = null;
    });

    try {
      final keyword = _searchQuery;
      final page = keyword != null && keyword.isNotEmpty
          ? await _controller.search(
              site: site,
              keyword: keyword,
              page: nextPage,
            )
          : await _controller.browse(
              site: site,
              categoryId: _category?.id,
              page: nextPage,
            );
      if (!mounted) return;
      if (token != _requestToken) return;
      setState(() {
        if (reset) {
          _items = page.items;
        } else {
          final seen = {for (final item in _items) item.id};
          _items = [
            ..._items,
            ...page.items.where((item) => seen.add(item.id)),
          ];
        }
        if (page.categories.isNotEmpty) {
          _categories = page.categories;
        } else if (reset) {
          _categories = const [];
        }
        _page = page.page;
        _pageCount = page.pageCount;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (token != _requestToken) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _selectSite(SubscriptionSite site) {
    if (!site.isSupported) {
      _toast(site.unsupportedReason);
      return;
    }
    if (_site?.key == site.key) return;
    setState(() {
      _site = site;
      _category = null;
      _searchQuery = null;
      _items = const [];
      _categories = const [];
    });
    _load(reset: true);
  }

  void _selectCategory(VodCategory? category) {
    if (_category?.id == category?.id) return;
    setState(() {
      _category = category;
      _items = const [];
    });
    _load(reset: true);
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    setState(() {
      _searchQuery = query;
      _searching = false;
      _category = null;
      _items = const [];
    });
    FocusScope.of(context).unfocus();
    _load(reset: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = null;
      _searching = false;
      _items = const [];
    });
    _load(reset: true);
  }

  Future<void> _switchRepo() async {
    final repos = _controller.repos;
    final selected = await showModalBottomSheet<SubscriptionRepo>(
      context: context,
      backgroundColor: AppColorScheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final repo in repos)
              ListTile(
                leading: Icon(
                  repo.id == _controller.activeRepoId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: AppColorScheme.accent,
                ),
                title: Text(repo.name),
                subtitle: Text(
                  '${repo.sites.length} 个站点',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(repo),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _controller.setActiveRepo(selected.id);
  }

  void _openVod(Vod vod) {
    final site = _site;
    if (site == null) return;
    final uri = Uri(
      path: Destinations.subscriptionDetail,
      queryParameters: {
        'siteKey': site.key,
        'vodId': vod.id,
        'name': vod.name,
      },
    );
    context.push(uri.toString());
  }

  void _playHistory(SubscriptionHistoryEntry entry) {
    if (entry.episodeUrl.isEmpty) return;
    context.push(
      Destinations.subscriptionPlayer,
      extra: {
        'title': entry.name,
        'pic': entry.pic,
        'vodId': entry.vodId,
        'siteKey': entry.siteKey,
        'sourceName': entry.sourceName,
        'repoId': entry.repoId,
        'playlist': [
          VodEpisode(name: entry.episodeName, url: entry.episodeUrl),
        ],
        'index': 0,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = _controller.activeRepo;
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      appBar: _buildAppBar(repo),
      body: repo == null ? _buildNoRepo() : _buildRepoBody(repo),
    );
  }

  AppBar _buildAppBar(SubscriptionRepo? repo) {
    if (_searching) {
      return AppBar(
        backgroundColor: AppColorScheme.background,
        foregroundColor: AppColorScheme.onBackground,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索影片',
            border: InputBorder.none,
          ),
          onSubmitted: _submitSearch,
        ),
        actions: [
          IconButton(
            tooltip: '关闭搜索',
            onPressed: _clearSearch,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    }
    return AppBar(
      backgroundColor: AppColorScheme.background,
      foregroundColor: AppColorScheme.onBackground,
      title: Text(
        repo?.name ?? '订阅源',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (repo != null)
          IconButton(
            tooltip: '搜索',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search_rounded),
          ),
        if (_controller.repos.length > 1)
          IconButton(
            tooltip: '切换订阅源',
            onPressed: _switchRepo,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
        if (repo != null)
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        IconButton(
          tooltip: '订阅源管理',
          onPressed: () => context.push(Destinations.subscriptionSources),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildNoRepo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rss_feed_rounded,
              size: 56,
              color: AppColorScheme.accent.withValues(alpha: 0.75),
            ),
            const SizedBox(height: AppSpacing.spaceLg),
            Text('还没有订阅源', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.spaceSm),
            Text(
              '添加一个饭太硬 / TVBox 格式的 JSON 订阅源，即可在这里浏览影片。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: AppSpacing.spaceXl),
            FilledButton.icon(
              onPressed: () => context.push(Destinations.subscriptionSources),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加订阅源'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepoBody(SubscriptionRepo repo) {
    if (repo.isMultiRepo && repo.selectedDepotUrl.isEmpty) {
      return _buildDepotChooser(repo);
    }
    if (repo.sites.where((site) => site.isSupported).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension_off_rounded,
                size: 52,
                color: AppColorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(height: AppSpacing.spaceLg),
              Text(
                '这个订阅源没有可直接访问的站点',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.spaceSm),
              Text(
                '配置里的站点都是 JS / Python / PHP / JAR 爬虫，'
                '需要 TVBox 原生解析内核，纯 Dart 订阅源模块暂不支持。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: AppSpacing.spaceXl),
              OutlinedButton.icon(
                onPressed: () => context.push(Destinations.subscriptionSources),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('更换订阅源'),
              ),
            ],
          ),
        ),
      );
    }

    final site = _site;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repo.sites.isNotEmpty) _buildSiteChips(repo),
        if (site != null && _categories.isNotEmpty) _buildCategoryChips(),
        if (_searchQuery != null && _searchQuery!.isNotEmpty)
          _buildSearchBanner(),
        if (site != null &&
            _searchQuery == null &&
            _category == null &&
            _controller.historyFor(
              repoId: repo.id,
              siteKey: site.key,
              limit: 10,
            ).isNotEmpty)
          _buildHistory(repo, site),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildDepotChooser(SubscriptionRepo repo) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('多仓订阅源', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.spaceSm),
          Text(
            '请选择一条仓库线路，之后可以在订阅源管理里随时切换。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: AppSpacing.spaceLg),
          Expanded(
            child: ListView.separated(
              itemCount: repo.depots.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.spaceSm),
              itemBuilder: (context, index) {
                final depot = repo.depots[index];
                return Material(
                  color: AppColorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(
                      Icons.account_tree_rounded,
                      color: AppColorScheme.accent,
                    ),
                    title: Text(depot.name),
                    subtitle: Text(
                      depot.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      try {
                        await _controller.selectDepot(repo.id, depot);
                        if (mounted) _load(reset: true);
                      } catch (error) {
                        if (mounted) _toast('加载线路失败：$error');
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteChips(SubscriptionRepo repo) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.spaceLg,
          vertical: AppSpacing.spaceSm,
        ),
        itemCount: repo.sites.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.spaceSm),
        itemBuilder: (context, index) {
          final site = repo.sites[index];
          final selected = site.key == _site?.key;
          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!site.isSupported) ...[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppColorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(site.name),
              ],
            ),
            selected: selected,
            onSelected: (_) => _selectSite(site),
            selectedColor: AppColorScheme.accent.withValues(alpha: 0.22),
            backgroundColor: AppColorScheme.surface,
            labelStyle: TextStyle(
              color: selected
                  ? AppColorScheme.accent
                  : AppColorScheme.onSurface.withValues(
                      alpha: site.isSupported ? 0.9 : 0.5,
                    ),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(
              color: selected
                  ? AppColorScheme.accent.withValues(alpha: 0.5)
                  : AppColorScheme.onSurface.withValues(alpha: 0.12),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.spaceLg,
          vertical: AppSpacing.spaceXs,
        ),
        itemCount: _categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.spaceSm),
        itemBuilder: (context, index) {
          final category = index == 0 ? null : _categories[index - 1];
          final selected = category?.id == _category?.id;
          return FilterChip(
            label: Text(category?.name ?? '全部'),
            selected: selected,
            onSelected: (_) => _selectCategory(category),
            selectedColor: AppColorScheme.accent.withValues(alpha: 0.22),
            backgroundColor: AppColorScheme.surface,
            labelStyle: TextStyle(
              color: selected
                  ? AppColorScheme.accent
                  : AppColorScheme.onSurface.withValues(alpha: 0.85),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(
              color: selected
                  ? AppColorScheme.accent.withValues(alpha: 0.5)
                  : AppColorScheme.onSurface.withValues(alpha: 0.12),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildSearchBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceSm,
        AppSpacing.spaceLg,
        AppSpacing.spaceXs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '搜索“${_searchQuery!}”的结果',
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _clearSearch,
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(SubscriptionRepo repo, SubscriptionSite site) {
    final entries = _controller.historyFor(
      repoId: repo.id,
      siteKey: site.key,
      limit: 10,
    );
    final cardWidth = 108.0;
    final height =
        MediaCard.layoutHeight(
              context,
              width: cardWidth,
              aspectRatio: 2 / 3,
              hasSubtitle: true,
            ) +
        AppSpacing.spaceMd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.spaceLg,
            AppSpacing.spaceSm,
            AppSpacing.spaceLg,
            AppSpacing.spaceXs,
          ),
          child: Text('继续观看', style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.spaceLg,
              vertical: AppSpacing.spaceXs,
            ),
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.spaceMd),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return MediaCard(
                width: cardWidth,
                aspectRatio: 2 / 3,
                title: entry.name,
                subtitle: entry.episodeName,
                imageUrl: entry.pic,
                playedPercentage: entry.progress,
                onTap: () => _playHistory(entry),
                onLongPress: () => _confirmRemoveHistory(entry),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemoveHistory(SubscriptionHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('移除观看记录'),
        content: Text('从“继续观看”里移除“${entry.name}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.removeHistoryEntry(entry);
    }
  }

  Widget _buildGrid() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppColorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(height: AppSpacing.spaceMd),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.spaceSm),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: AppSpacing.spaceLg),
              FilledButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.spaceXl),
          child: Text(
            _searchQuery != null ? '没有搜索到影片' : '这个分类暂时没有影片',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 240 &&
            !_loading &&
            _page < _pageCount) {
          _load();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        color: AppColorScheme.accent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth >= 700
                ? 5
                : constraints.maxWidth >= 520
                    ? 4
                    : 3;
            const spacing = AppSpacing.spaceMd;
            final width = (constraints.maxWidth -
                    spacing * (count + 1)) /
                count;
            final extent =
                MediaCard.layoutHeight(
                  context,
                  width: width,
                  aspectRatio: 2 / 3,
                  hasSubtitle: true,
                ) +
                4;

            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(spacing),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: extent,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final vod = _items[index];
                return MediaCard(
                  width: width,
                  aspectRatio: 2 / 3,
                  title: vod.name,
                  subtitle: vod.displayRemarks,
                  imageUrl: vod.pic,
                  onTap: () => _openVod(vod),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
