import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../auth/models/server.dart';
import '../../auth/repositories/server_repository.dart';
import '../../auth/repositories/session_repository.dart';
import '../../ui/navigation/destinations.dart';
import '../models/subscription_models.dart';
import '../state/subscription_controller.dart';

/// 未登录媒体服务器时也能使用的入口页。
///
/// 顶部直接提供“添加媒体库”和“添加订阅源”，底部是媒体库 / 订阅 / 我的三个
/// 导航入口。
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _controller = SubscriptionController.instance;
  final _serverRepo = GetIt.instance<ServerRepository>();
  final _sessionRepo = GetIt.instance<SessionRepository>();

  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller.ensureLoaded();
    _refreshServers();
  }

  Future<void> _refreshServers() async {
    await _serverRepo.loadStoredServers();
    if (mounted) setState(() {});
  }

  Future<void> _addMediaLibrary() async {
    await context.push(Destinations.serverSelect);
    if (mounted) setState(() {});
  }

  Future<void> _addSubscription() async {
    await context.push(Destinations.subscriptionSources);
    if (mounted) setState(() {});
  }

  void _openServer(Server server) {
    context.push('${Destinations.server}?serverId=${server.id}');
  }

  void _openSubscriptionHome() {
    context.push(Destinations.subscription);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _LibraryTab(
              servers: _serverRepo.servers,
              sessionActive: _sessionRepo.activeUserId != null,
              onAddMediaLibrary: _addMediaLibrary,
              onAddSubscription: _addSubscription,
              onOpenServer: _openServer,
              onContinueToHome: () => context.go(Destinations.home),
            ),
            _SubscriptionTab(
              controller: _controller,
              onAdd: _addSubscription,
              onOpenHome: _openSubscriptionHome,
              onManage: () => context.push(Destinations.subscriptionSources),
            ),
            _MineTab(
              onManageSources: () => context.push(Destinations.subscriptionSources),
              onManageServers: _addMediaLibrary,
              onClearHistory: _clearHistory,
              onAbout: _showAbout,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    const items = [
      (Icons.video_library_outlined, Icons.video_library_rounded, '媒体库'),
      (Icons.rss_feed_outlined, Icons.rss_feed_rounded, '订阅'),
      (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        border: Border(
          top: BorderSide(
            color: AppColorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: NavigationBar(
        height: 62,
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColorScheme.accent.withValues(alpha: 0.16),
        selectedIndex: _tabIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(
                item.$1,
                color: AppColorScheme.onSurface.withValues(alpha: 0.65),
              ),
              selectedIcon: Icon(item.$2, color: AppColorScheme.accent),
              label: item.$3,
            ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('清空观看记录'),
        content: const Text('只清空订阅源的本地观看记录，不影响媒体库的历史。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.clearHistory();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已清空订阅源观看记录')));
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('关于'),
        content: const Text(
          '订阅源模块独立于 Moonfin 媒体库，支持饭太硬 / TVBox 格式的 JSON 配置、'
          '多仓线路、选集与多线路切换。\n\n'
          '订阅源数据保存在本机，不会写入 Emby / Jellyfin 服务器。\n'
          'JS / Python / PHP / JAR 爬虫站点需要 TVBox 原生内核，当前仅支持 '
          'XML 与 JSON 接口站点。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.servers,
    required this.sessionActive,
    required this.onAddMediaLibrary,
    required this.onAddSubscription,
    required this.onOpenServer,
    required this.onContinueToHome,
  });

  final List<Server> servers;
  final bool sessionActive;
  final VoidCallback onAddMediaLibrary;
  final VoidCallback onAddSubscription;
  final ValueChanged<Server> onOpenServer;
  final VoidCallback onContinueToHome;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceXl,
      ),
      children: [
        Image.asset(
          'assets/images/logo_and_text.png',
          height: 44,
          alignment: Alignment.centerLeft,
        ),
        const SizedBox(height: AppSpacing.spaceLg),
        Text(
          '开始使用',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.spaceXs),
        Text(
          '连接你的 Emby / Jellyfin 媒体库，或直接添加订阅源看片。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorScheme.onSurface.withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: AppSpacing.spaceLg),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.add_to_queue_rounded,
                title: '添加媒体库',
                subtitle: 'Emby / Jellyfin',
                primary: true,
                onTap: onAddMediaLibrary,
              ),
            ),
            const SizedBox(width: AppSpacing.spaceMd),
            Expanded(
              child: _ActionCard(
                icon: Icons.rss_feed_rounded,
                title: '添加订阅源',
                subtitle: 'JSON / 多仓',
                primary: false,
                onTap: onAddSubscription,
              ),
            ),
          ],
        ),
        if (sessionActive) ...[
          const SizedBox(height: AppSpacing.spaceLg),
          FilledButton.icon(
            onPressed: onContinueToHome,
            icon: const Icon(Icons.login_rounded),
            label: const Text('继续进入媒体库'),
          ),
        ],
        const SizedBox(height: AppSpacing.spaceXl),
        Row(
          children: [
            Text('我的媒体服务器', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: onAddMediaLibrary,
              child: const Text('添加'),
            ),
          ],
        ),
        if (servers.isEmpty)
          _HintCard(
            icon: Icons.dns_outlined,
            title: '还没有添加媒体库',
            message: '点击上方“添加媒体库”，输入 Emby / Jellyfin 服务器地址。',
          )
        else
          for (final server in servers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.spaceSm),
              child: Material(
                color: AppColorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => onOpenServer(server),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColorScheme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      color: AppColorScheme.accent,
                    ),
                  ),
                  title: Text(server.name),
                  subtitle: Text(
                    server.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.spaceXl),
        Text('订阅源', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.spaceSm),
        _HintCard(
          icon: Icons.rss_feed_rounded,
          title: 'JSON 订阅源',
          message: '添加饭太硬 / TVBox 格式的 JSON 配置，支持多仓、选集与多线路切换。',
          actionLabel: '添加订阅源',
          onAction: onAddSubscription,
        ),
      ],
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  const _SubscriptionTab({
    required this.controller,
    required this.onAdd,
    required this.onOpenHome,
    required this.onManage,
  });

  final SubscriptionController controller;
  final VoidCallback onAdd;
  final VoidCallback onOpenHome;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final repos = controller.repos;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.spaceLg,
            AppSpacing.spaceLg,
            AppSpacing.spaceLg,
            AppSpacing.spaceXl,
          ),
          children: [
            Row(
              children: [
                Text('订阅源', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                IconButton(
                  tooltip: '管理订阅源',
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: '添加订阅源',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.spaceXs),
            Text(
              '观看记录与收藏都保存在本机，不写入 Emby / Jellyfin。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: AppSpacing.spaceXl),
            if (repos.isEmpty)
              _HintCard(
                icon: Icons.rss_feed_rounded,
                title: '还没有订阅源',
                message: '添加一个饭太硬 / TVBox 格式的 JSON 订阅地址即可开始。',
                actionLabel: '添加订阅源',
                onAction: onAdd,
              )
            else ...[
              for (final repo in repos)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.spaceSm),
                  child: _RepoRow(
                    repo: repo,
                    active: repo.id == controller.activeRepoId,
                    onTap: () async {
                      await controller.setActiveRepo(repo.id);
                      onOpenHome();
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.spaceLg),
              FilledButton.icon(
                onPressed: onOpenHome,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('进入订阅源'),
              ),
            ],
            if (controller.history.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.spaceXl),
              Row(
                children: [
                  Text('最近观看', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: onOpenHome,
                    child: const Text('全部'),
                  ),
                ],
              ),
              for (final entry in controller.history.take(3))
                _HistoryRow(entry: entry),
            ],
          ],
        );
      },
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({
    required this.repo,
    required this.active,
    required this.onTap,
  });

  final SubscriptionRepo repo;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = repo.isMultiRepo && repo.selectedDepotUrl.isEmpty
        ? '多仓 · ${repo.depots.length} 条线路，尚未选择'
        : '${repo.sites.length} 个站点';
    return Material(
      color: AppColorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColorScheme.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.rss_feed_rounded, color: AppColorScheme.accent),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                repo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (active) ...[
              const SizedBox(width: AppSpacing.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: AppColorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SubscriptionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.spaceSm),
      child: Material(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: AppColorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            entry.episodeName.isEmpty ? entry.sourceName : entry.episodeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: entry.episodeUrl.isEmpty
              ? null
              : () => context.push(
                    Destinations.subscriptionPlayer,
                    extra: {
                      'title': entry.name,
                      'pic': entry.pic,
                      'vodId': entry.vodId,
                      'siteKey': entry.siteKey,
                      'sourceName': entry.sourceName,
                      'repoId': entry.repoId,
                      'playlist': [
                        VodEpisode(
                          name: entry.episodeName,
                          url: entry.episodeUrl,
                        ),
                      ],
                      'index': 0,
                    },
                  ),
        ),
      ),
    );
  }
}

class _MineTab extends StatelessWidget {
  const _MineTab({
    required this.onManageSources,
    required this.onManageServers,
    required this.onClearHistory,
    required this.onAbout,
  });

  final VoidCallback onManageSources;
  final VoidCallback onManageServers;
  final VoidCallback onClearHistory;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceLg,
        AppSpacing.spaceXl,
      ),
      children: [
        Text('我的', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.spaceLg),
        _MineTile(
          icon: Icons.rss_feed_rounded,
          title: '订阅源管理',
          subtitle: '添加、编辑、删除、切换订阅源与多仓线路',
          onTap: onManageSources,
        ),
        _MineTile(
          icon: Icons.dns_rounded,
          title: '媒体服务器',
          subtitle: '添加或切换 Emby / Jellyfin 服务器',
          onTap: onManageServers,
        ),
        _MineTile(
          icon: Icons.history_rounded,
          title: '清空观看记录',
          subtitle: '只清理订阅源本地记录',
          onTap: onClearHistory,
        ),
        _MineTile(
          icon: Icons.info_outline_rounded,
          title: '关于订阅源模块',
          subtitle: '支持的接口类型与限制',
          onTap: onAbout,
        ),
        const SizedBox(height: AppSpacing.spaceXl),
        Center(
          child: Text(
            'Moonfin · 订阅源模块',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ),
      ],
    );
  }
}

class _MineTile extends StatelessWidget {
  const _MineTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.spaceSm),
      child: Material(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: AppColorScheme.accent),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background =
        primary ? AppColorScheme.accent : AppColorScheme.surface;
    final foreground =
        primary ? AppColorScheme.onAccent : AppColorScheme.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 26),
              const SizedBox(height: AppSpacing.spaceMd),
              Text(
                title,
                style: TextStyle(
                  color: foreground,
                  fontSize: AppTypography.fontSizeMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.7),
                  fontSize: AppTypography.fontSizeXs,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.spaceLg),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColorScheme.accent),
          const SizedBox(width: AppSpacing.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: AppSpacing.spaceSm),
                  TextButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
