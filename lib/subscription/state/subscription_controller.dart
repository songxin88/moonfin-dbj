/// 订阅源模块的状态中心。
///
/// 单例 + ChangeNotifier，不注册进 Moonfin 的 GetIt，避免影响原有依赖图。
library;

import 'package:flutter/foundation.dart';

import '../data/subscription_store.dart';
import '../data/tvbox_api.dart';
import '../models/subscription_models.dart';

class SubscriptionController extends ChangeNotifier {
  SubscriptionController._();

  static final SubscriptionController instance = SubscriptionController._();

  final TvboxApi api = TvboxApi();
  final SubscriptionStore store = SubscriptionStore();

  List<SubscriptionRepo> _repos = const [];
  List<SubscriptionHistoryEntry> _history = const [];
  String? _activeRepoId;
  Future<void>? _loading;

  List<SubscriptionRepo> get repos => _repos;
  List<SubscriptionHistoryEntry> get history => _history;
  String? get activeRepoId => _activeRepoId;

  SubscriptionRepo? get activeRepo {
    for (final repo in _repos) {
      if (repo.id == _activeRepoId) return repo;
    }
    return _repos.isEmpty ? null : _repos.first;
  }

  SubscriptionSite? siteOf(SubscriptionRepo repo, String key) {
    for (final site in repo.sites) {
      if (site.key == key) return site;
    }
    return null;
  }

  List<SubscriptionSite> get supportedSites =>
      activeRepo?.sites.where((site) => site.isSupported).toList() ?? const [];

  /// 首次进入订阅源页面时加载本地数据。
  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _repos = await store.loadRepos();
    _history = await store.loadHistory();
    _activeRepoId = await store.loadActiveRepoId();
    if (_activeRepoId == null && _repos.isNotEmpty) {
      _activeRepoId = _repos.first.id;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await store.saveRepos(_repos);
    await store.saveActiveRepoId(_activeRepoId);
  }

  // ---------------------------------------------------------------------------
  // 订阅源管理
  // ---------------------------------------------------------------------------

  /// 添加一个订阅地址。多仓配置只保存仓库列表，站点需要用户再选一条线路。
  Future<SubscriptionRepo> addRepo({
    required String url,
    String? name,
  }) async {
    await ensureLoaded();
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) throw TvboxException('订阅地址不能为空');

    final config = await api.fetchConfig(trimmedUrl);
    if (config.depots.isEmpty && config.sites.isEmpty) {
      throw TvboxException('订阅配置里没有可用的站点或仓库线路');
    }

    final repo = SubscriptionRepo(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : _suggestName(trimmedUrl),
      url: trimmedUrl,
      isMultiRepo: config.isMultiRepo,
      depots: config.depots,
      sites: config.sites,
      parses: config.parses,
      spider: config.spider,
      updatedAt: DateTime.now(),
    );

    _repos = [..._repos, repo];
    _activeRepoId ??= repo.id;
    await _persist();
    notifyListeners();
    return repo;
  }

  /// 给多仓订阅源选择一条仓库线路，并加载该线路的站点。
  Future<SubscriptionRepo> selectDepot(
    String repoId,
    SubscriptionDepot depot,
  ) async {
    await ensureLoaded();
    final config = await api.fetchConfig(depot.url);
    if (config.depots.isNotEmpty && config.sites.isEmpty) {
      throw TvboxException('“${depot.name}”本身又是一个多仓配置，暂不支持嵌套');
    }

    final index = _indexOf(repoId);
    if (index < 0) throw TvboxException('订阅源不存在');
    final repo = _repos[index].copyWith(
      isMultiRepo: false,
      selectedDepotUrl: depot.url,
      sites: config.sites,
      parses: config.parses,
      spider: config.spider,
      updatedAt: DateTime.now(),
    );
    _repos = [..._repos]..[index] = repo;
    await _persist();
    notifyListeners();
    return repo;
  }

  /// 重新读取订阅配置。多仓订阅源会保留已选中的线路。
  Future<SubscriptionRepo> refreshRepo(String repoId) async {
    await ensureLoaded();
    final index = _indexOf(repoId);
    if (index < 0) throw TvboxException('订阅源不存在');
    final repo = _repos[index];
    final source =
        repo.selectedDepotUrl.isNotEmpty ? repo.selectedDepotUrl : repo.url;
    if (repo.isMultiRepo && repo.selectedDepotUrl.isEmpty) {
      throw TvboxException('多仓订阅源请先选择一条仓库线路');
    }

    final config = await api.fetchConfig(source);
    final updated = repo.copyWith(
      isMultiRepo: config.isMultiRepo,
      depots: config.depots.isEmpty ? repo.depots : config.depots,
      sites: config.sites,
      parses: config.parses,
      spider: config.spider,
      updatedAt: DateTime.now(),
    );
    _repos = [..._repos]..[index] = updated;
    await _persist();
    notifyListeners();
    return updated;
  }

  /// 修改名称/地址。地址变化时会重新加载配置。
  Future<void> updateRepo(
    String repoId, {
    String? name,
    String? url,
  }) async {
    await ensureLoaded();
    final index = _indexOf(repoId);
    if (index < 0) throw TvboxException('订阅源不存在');
    final repo = _repos[index];
    final nextUrl = url?.trim();
    var updated = repo.copyWith(
      name: name?.trim().isNotEmpty == true ? name!.trim() : repo.name,
    );

    if (nextUrl != null && nextUrl.isNotEmpty && nextUrl != repo.url) {
      final config = await api.fetchConfig(nextUrl);
      updated = updated.copyWith(
        url: nextUrl,
        isMultiRepo: config.isMultiRepo,
        depots: config.depots,
        selectedDepotUrl: '',
        sites: config.sites,
        parses: config.parses,
        spider: config.spider,
        updatedAt: DateTime.now(),
      );
    } else {
      updated = updated.copyWith(updatedAt: DateTime.now());
    }

    _repos = [..._repos]..[index] = updated;
    await _persist();
    notifyListeners();
  }

  Future<void> removeRepo(String repoId) async {
    await ensureLoaded();
    _repos = _repos.where((repo) => repo.id != repoId).toList();
    if (_activeRepoId == repoId) {
      _activeRepoId = _repos.isEmpty ? null : _repos.first.id;
    }
    _history = _history.where((entry) => entry.repoId != repoId).toList();
    await store.saveHistory(_history);
    await _persist();
    notifyListeners();
  }

  Future<void> setActiveRepo(String repoId) async {
    if (_activeRepoId == repoId) return;
    _activeRepoId = repoId;
    await store.saveActiveRepoId(repoId);
    notifyListeners();
  }

  int _indexOf(String repoId) {
    for (var index = 0; index < _repos.length; index++) {
      if (_repos[index].id == repoId) return index;
    }
    return -1;
  }

  String _suggestName(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isNotEmpty) return host;
    return '订阅源';
  }

  // ---------------------------------------------------------------------------
  // 接口请求
  // ---------------------------------------------------------------------------

  Future<VodPage> browse({
    required SubscriptionSite site,
    String? categoryId,
    int page = 1,
  }) {
    if (categoryId == null || categoryId.isEmpty) {
      return api.home(site, page: page);
    }
    return api.category(site, categoryId: categoryId, page: page);
  }

  Future<VodPage> search({
    required SubscriptionSite site,
    required String keyword,
    int page = 1,
  }) {
    return api.search(site, keyword, page: page);
  }

  Future<Vod> loadDetail({
    required SubscriptionSite site,
    required String vodId,
  }) {
    return api.detail(site, vodId);
  }

  Future<ResolvedPlayUrl> resolvePlayUrl({
    required SubscriptionRepo repo,
    required SubscriptionSite site,
    required String sourceName,
    required String rawUrl,
  }) {
    return api.resolvePlayUrl(
      rawUrl: rawUrl,
      site: site,
      sourceName: sourceName,
      parses: repo.parses,
    );
  }

  // ---------------------------------------------------------------------------
  // 播放历史（只属于订阅源模块）
  // ---------------------------------------------------------------------------

  List<SubscriptionHistoryEntry> historyFor({
    required String repoId,
    required String siteKey,
    int limit = 20,
  }) {
    final entries = _history
        .where((entry) => entry.repoId == repoId && entry.siteKey == siteKey)
        .toList()
      ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return entries.take(limit).toList();
  }

  SubscriptionHistoryEntry? historyForVod({
    required String repoId,
    required String siteKey,
    required String vodId,
  }) {
    for (final entry in _history) {
      if (entry.repoId == repoId &&
          entry.siteKey == siteKey &&
          entry.vodId == vodId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> upsertHistory({
    required String repoId,
    required String siteKey,
    required String vodId,
    required String name,
    required String pic,
    required String sourceName,
    required String episodeName,
    required String episodeUrl,
    required Duration position,
    required Duration duration,
  }) async {
    if (vodId.isEmpty) return;
    final entry = SubscriptionHistoryEntry(
      repoId: repoId,
      siteKey: siteKey,
      vodId: vodId,
      name: name,
      pic: pic,
      sourceName: sourceName,
      episodeName: episodeName,
      episodeUrl: episodeUrl,
      position: position,
      duration: duration,
      viewedAt: DateTime.now(),
    );
    final kept = <SubscriptionHistoryEntry>[
      for (final old in _history)
        if (!(old.repoId == repoId &&
            old.siteKey == siteKey &&
            old.vodId == vodId))
          old,
      entry,
    ];
    kept.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    _history = kept.take(60).toList();
    await store.saveHistory(_history);
    notifyListeners();
  }

  Future<void> removeHistoryEntry(SubscriptionHistoryEntry entry) async {
    _history = _history
        .where(
          (item) =>
              !(item.repoId == entry.repoId &&
                  item.siteKey == entry.siteKey &&
                  item.vodId == entry.vodId),
        )
        .toList();
    await store.saveHistory(_history);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = const [];
    await store.saveHistory(_history);
    notifyListeners();
  }
}
