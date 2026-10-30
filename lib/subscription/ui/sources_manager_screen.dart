import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../ui/navigation/destinations.dart';
import '../data/tvbox_api.dart';
import '../models/subscription_models.dart';
import '../state/subscription_controller.dart';

class SourcesManagerScreen extends StatefulWidget {
  const SourcesManagerScreen({super.key});

  @override
  State<SourcesManagerScreen> createState() => _SourcesManagerScreenState();
}

class _SourcesManagerScreenState extends State<SourcesManagerScreen> {
  final _controller = SubscriptionController.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      appBar: AppBar(
        backgroundColor: AppColorScheme.background,
        foregroundColor: AppColorScheme.onBackground,
        title: const Text('订阅源管理'),
        actions: [
          IconButton(
            tooltip: '添加订阅源',
            onPressed: _busy ? null : _addSource,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final repos = _controller.repos;
          if (repos.isEmpty) {
            return _EmptySources(onAdd: _busy ? null : _addSource);
          }
          return Stack(
            children: [
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.spaceLg,
                  AppSpacing.spaceSm,
                  AppSpacing.spaceLg,
                  AppSpacing.space3xl,
                ),
                itemCount: repos.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.spaceSm),
                itemBuilder: (context, index) {
                  final repo = repos[index];
                  return _RepoCard(
                    repo: repo,
                    active: repo.id == _controller.activeRepoId,
                    onTap: () => _openRepo(repo),
                    onMenu: (value) => _onMenu(repo, value),
                  );
                },
              ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRepo(SubscriptionRepo repo) async {
    await _controller.setActiveRepo(repo.id);
    if (!mounted) return;
    if (repo.isMultiRepo && repo.selectedDepotUrl.isEmpty) {
      await _chooseDepot(repo);
      return;
    }
    if (repo.sites.isEmpty) {
      _toast('该订阅源没有可用的站点，试试刷新配置');
      return;
    }
    context.push(Destinations.subscription);
  }

  Future<void> _onMenu(SubscriptionRepo repo, String action) async {
    switch (action) {
      case 'active':
        await _controller.setActiveRepo(repo.id);
      case 'refresh':
        await _refresh(repo);
      case 'edit':
        await _edit(repo);
      case 'depot':
        await _chooseDepot(repo);
      case 'delete':
        await _delete(repo);
    }
  }

  Future<void> _refresh(SubscriptionRepo repo) async {
    setState(() => _busy = true);
    try {
      final updated = await _controller.refreshRepo(repo.id);
      if (!mounted) return;
      _toast('已刷新：${updated.sites.length} 个站点');
    } on TvboxException catch (error) {
      if (!mounted) return;
      if (repo.isMultiRepo && repo.selectedDepotUrl.isEmpty) {
        await _chooseDepot(repo);
      } else {
        _toast(error.message);
      }
    } catch (error) {
      if (mounted) _toast('刷新失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDepot(SubscriptionRepo repo) async {
    if (repo.depots.isEmpty) {
      _toast('该订阅源没有仓库线路');
      return;
    }
    final depot = await showModalBottomSheet<SubscriptionDepot>(
      context: context,
      backgroundColor: AppColorScheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.spaceLg,
                AppSpacing.spaceXs,
                AppSpacing.spaceLg,
                AppSpacing.spaceSm,
              ),
              child: Text(
                '选择仓库线路',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: repo.depots.length,
                itemBuilder: (context, index) {
                  final item = repo.depots[index];
                  final selected = item.url == repo.selectedDepotUrl;
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? AppColorScheme.accent
                          : AppColorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      item.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.spaceSm),
          ],
        ),
      ),
    );
    if (depot == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _controller.selectDepot(repo.id, depot);
      await _controller.setActiveRepo(updated.id);
      if (!mounted) return;
      _toast('已切换到“${depot.name}”，共 ${updated.sites.length} 个站点');
    } on TvboxException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('加载线路失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSource() async {
    final draft = await showDialog<_SourceDraft>(
      context: context,
      builder: (context) => const _SourceDialog(),
    );
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = await _controller.addRepo(
        url: draft.url,
        name: draft.name,
      );
      await _controller.setActiveRepo(repo.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (repo.isMultiRepo) {
        await _chooseDepot(repo);
        return;
      }
      _toast('已添加订阅源，共 ${repo.sites.length} 个站点');
    } on TvboxException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('添加失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(SubscriptionRepo repo) async {
    final draft = await showDialog<_SourceDraft>(
      context: context,
      builder: (context) => _SourceDialog(repo: repo),
    );
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _controller.updateRepo(
        repo.id,
        name: draft.name,
        url: draft.url,
      );
      if (mounted) _toast('已保存');
    } on TvboxException catch (error) {
      if (mounted) _toast(error.message);
    } catch (error) {
      if (mounted) _toast('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SubscriptionRepo repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('删除订阅源'),
        content: Text('确定删除“${repo.name}”吗？相关的本地观看历史也会一起删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.removeRepo(repo.id);
    if (mounted) _toast('已删除');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.repo,
    required this.active,
    required this.onTap,
    required this.onMenu,
  });

  final SubscriptionRepo repo;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final supported = repo.sites.where((site) => site.isSupported).length;
    final subtitle = repo.isMultiRepo && repo.selectedDepotUrl.isEmpty
        ? '多仓 · ${repo.depots.length} 条线路，尚未选择'
        : '${repo.sites.length} 个站点 · $supported 个可直接访问';

    return Material(
      color: AppColorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.spaceLg,
            AppSpacing.spaceMd,
            AppSpacing.spaceXs,
            AppSpacing.spaceMd,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColorScheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.rss_feed_rounded,
                  color: AppColorScheme.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            repo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: AppSpacing.spaceSm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColorScheme.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '当前',
                              style: TextStyle(
                                fontSize: AppTypography.fontSize2xs,
                                color: AppColorScheme.onAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      repo.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColorScheme.onSurface.withValues(
                              alpha: 0.75,
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppColorScheme.onSurface.withValues(alpha: 0.75),
                ),
                onSelected: onMenu,
                itemBuilder: (context) => [
                  if (!active)
                    const PopupMenuItem(value: 'active', child: Text('设为当前订阅源')),
                  const PopupMenuItem(value: 'refresh', child: Text('刷新配置')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑名称/地址')),
                  if (repo.isMultiRepo)
                    const PopupMenuItem(value: 'depot', child: Text('选择仓库线路')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySources extends StatelessWidget {
  const _EmptySources({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
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
              '支持饭太硬 / TVBox 格式 JSON 配置，可添加多仓线路。\n'
              '订阅源与 Emby / Jellyfin 媒体库互不影响。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: AppSpacing.spaceXl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加订阅源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceDraft {
  const _SourceDraft({required this.name, required this.url});

  final String name;
  final String url;
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog({this.repo});

  final SubscriptionRepo? repo;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.repo?.name ?? '');
    _urlController = TextEditingController(text: widget.repo?.url ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.repo != null;
    return AlertDialog.adaptive(
      title: Text(editing ? '编辑订阅源' : '添加订阅源'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '订阅地址',
                hintText: 'http://example.com/config.json',
              ),
            ),
            const SizedBox(height: AppSpacing.spaceMd),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                hintText: '不填则使用域名',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.spaceMd),
            Text(
              '支持饭太硬 / TVBox JSON 配置，多仓配置添加后会提示选择线路。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.65),
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? '保存' : '添加'),
        ),
      ],
    );
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请填写订阅地址')));
      return;
    }
    Navigator.of(context).pop(
      _SourceDraft(name: _nameController.text.trim(), url: url),
    );
  }
}
