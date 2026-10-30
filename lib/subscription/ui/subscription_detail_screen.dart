import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../ui/navigation/destinations.dart';
import '../models/subscription_models.dart';
import '../state/subscription_controller.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  const SubscriptionDetailScreen({
    super.key,
    required this.siteKey,
    required this.vodId,
    this.vodName = '',
  });

  final String siteKey;
  final String vodId;
  final String vodName;

  @override
  State<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  final _controller = SubscriptionController.instance;

  SubscriptionRepo? _repo;
  SubscriptionSite? _site;
  Vod? _vod;
  bool _loading = true;
  bool _resolving = false;
  bool _expanded = false;
  String? _error;
  int _sourceIndex = 0;
  int _episodeIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _controller.ensureLoaded();
    if (!mounted) return;
    final repo = _controller.activeRepo;
    final site = repo == null ? null : _controller.siteOf(repo, widget.siteKey);
    if (repo == null || site == null) {
      setState(() {
        _loading = false;
        _error = '找不到这个站点，可能订阅源已被删除或配置已更新。';
      });
      return;
    }
    _repo = repo;
    _site = site;
    await _loadDetail();
  }

  Future<void> _loadDetail() async {
    final site = _site;
    if (site == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vod = await _controller.loadDetail(
        site: site,
        vodId: widget.vodId,
      );
      if (!mounted) return;
      var sourceIndex = 0;
      var episodeIndex = 0;
      final history = _controller.historyForVod(
        repoId: _repo!.id,
        siteKey: site.key,
        vodId: vod.id,
      );
      if (history != null) {
        for (var index = 0; index < vod.sources.length; index++) {
          if (vod.sources[index].name == history.sourceName) {
            sourceIndex = index;
            for (var ep = 0; ep < vod.sources[index].episodes.length; ep++) {
              if (vod.sources[index].episodes[ep].name == history.episodeName) {
                episodeIndex = ep;
                break;
              }
            }
            break;
          }
        }
      }
      setState(() {
        _vod = vod;
        _loading = false;
        _sourceIndex = sourceIndex;
        _episodeIndex = episodeIndex;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _play(int index) async {
    final vod = _vod;
    final site = _site;
    final repo = _repo;
    if (vod == null || site == null || repo == null) return;
    if (vod.sources.isEmpty) {
      _toast('这个影片没有播放线路');
      return;
    }
    final source = vod.sources[_sourceIndex.clamp(0, vod.sources.length - 1)];
    if (index < 0 || index >= source.episodes.length) return;

    setState(() => _resolving = true);
    try {
      final resolved = await _controller.resolvePlayUrl(
        repo: repo,
        site: site,
        sourceName: source.name,
        rawUrl: source.episodes[index].url,
      );
      if (!mounted) return;
      setState(() {
        _episodeIndex = index;
        _resolving = false;
      });
      await context.push(
        Destinations.subscriptionPlayer,
        extra: {
          'title': vod.name,
          'pic': vod.pic,
          'vodId': vod.id,
          'siteKey': site.key,
          'sourceName': source.name,
          'repoId': repo.id,
          'playlist': source.episodes,
          'index': index,
          'initialUrl': resolved.url,
        },
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _resolving = false);
        _toast('无法播放：$error');
      }
    }
  }

  void _selectSource(int index) {
    if (index == _sourceIndex) return;
    setState(() {
      _sourceIndex = index;
      _episodeIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vod = _vod;
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      appBar: AppBar(
        backgroundColor: AppColorScheme.background,
        foregroundColor: AppColorScheme.onBackground,
        title: Text(
          vod?.name.isNotEmpty == true ? vod!.name : widget.vodName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新详情',
            onPressed: _loading ? null : _loadDetail,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
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
              Text('加载失败', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.spaceSm),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: AppSpacing.spaceLg),
              FilledButton(onPressed: _loadDetail, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final vod = _vod;
    if (vod == null) {
      return const Center(child: Text('没有影片信息'));
    }
    final sources = vod.sources;
    final source = sources.isEmpty
        ? null
        : sources[_sourceIndex.clamp(0, sources.length - 1)];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(vod)),
        SliverToBoxAdapter(child: _buildActions(vod, source)),
        if (sources.length > 1)
          SliverToBoxAdapter(child: _buildSourceChips(sources)),
        if (source != null)
          SliverToBoxAdapter(child: _buildEpisodeHeader(source)),
        if (source != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.spaceLg,
              0,
              AppSpacing.spaceLg,
              AppSpacing.spaceXl,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.spaceSm,
                crossAxisSpacing: AppSpacing.spaceSm,
                mainAxisExtent: 42,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final episode = source.episodes[index];
                  final selected = index == _episodeIndex;
                  return Material(
                    color: selected
                        ? AppColorScheme.accent.withValues(alpha: 0.22)
                        : AppColorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _play(index),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.spaceSm,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppColorScheme.accent.withValues(alpha: 0.6)
                                : AppColorScheme.onSurface.withValues(
                                    alpha: 0.12,
                                  ),
                          ),
                        ),
                        child: Text(
                          episode.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTypography.fontSizeXs,
                            color: selected
                                ? AppColorScheme.accent
                                : AppColorScheme.onSurface.withValues(
                                    alpha: 0.9,
                                  ),
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: source.episodes.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.spaceXl)),
      ],
    );
  }

  Widget _buildHeader(Vod vod) {
    final meta = [
      if (vod.year.isNotEmpty) vod.year,
      if (vod.area.isNotEmpty) vod.area,
      if (vod.typeName.isNotEmpty) vod.typeName,
      if (vod.language.isNotEmpty) vod.language,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceMd,
        AppSpacing.spaceLg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 112,
              height: 168,
              child: vod.pic.isEmpty
                  ? Container(
                      color: AppColorScheme.surfaceVariant,
                      child: Icon(
                        Icons.movie_outlined,
                        color: AppColorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    )
                  : Image.network(
                      vod.pic,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: AppColorScheme.surfaceVariant,
                        child: Icon(
                          Icons.movie_outlined,
                          color:
                              AppColorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppColorScheme.surfaceVariant,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.spaceLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vod.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (vod.remarks.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    vod.remarks,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColorScheme.accent,
                        ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.spaceSm),
                  Text(
                    meta,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                ],
                if (vod.score.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.spaceSm),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColorScheme.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        vod.score,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                if (vod.actor.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.spaceSm),
                  Text(
                    '主演：${vod.actor}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                ],
                if (vod.director.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '导演：${vod.director}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(Vod vod, VodPlaySource? source) {
    final episodes = source?.episodes ?? const <VodEpisode>[];
    final hasEpisode = episodes.isNotEmpty;
    final episodeIndex =
        hasEpisode ? _episodeIndex.clamp(0, episodes.length - 1) : 0;
    final episodeName = hasEpisode ? episodes[episodeIndex].name : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: hasEpisode && !_resolving
                ? () => _play(episodeIndex)
                : null,
            icon: _resolving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(
              hasEpisode ? '播放 $episodeName' : '暂无播放地址',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (vod.content.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.spaceMd),
            Text(
              vod.content,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: AppColorScheme.onSurface.withValues(alpha: 0.78),
                  ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceChips(List<VodPlaySource> sources) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.spaceLg,
          vertical: AppSpacing.spaceSm,
        ),
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.spaceSm),
        itemBuilder: (context, index) {
          final source = sources[index];
          final selected = index == _sourceIndex;
          return ChoiceChip(
            label: Text('${source.name} (${source.episodes.length})'),
            selected: selected,
            onSelected: (_) => _selectSource(index),
            selectedColor: AppColorScheme.accent.withValues(alpha: 0.22),
            backgroundColor: AppColorScheme.surface,
            labelStyle: TextStyle(
              color: selected
                  ? AppColorScheme.accent
                  : AppColorScheme.onSurface.withValues(alpha: 0.9),
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

  Widget _buildEpisodeHeader(VodPlaySource source) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceSm,
        AppSpacing.spaceLg,
        AppSpacing.spaceSm,
      ),
      child: Row(
        children: [
          Text('选集', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: AppSpacing.spaceSm),
          Text(
            '共 ${source.episodes.length} 集 · ${source.name}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ],
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
