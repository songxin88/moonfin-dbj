/// 订阅源模块的本地持久化。
///
/// 使用独立的 SharedPreferences key 前缀，不写入 Moonfin 的偏好设置，
/// 这样订阅源数据与媒体服务器账号互不干扰。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_models.dart';

class SubscriptionStore {
  static const _reposKey = 'moonfin_subscription_repos_v1';
  static const _activeRepoKey = 'moonfin_subscription_active_repo_v1';
  static const _historyKey = 'moonfin_subscription_history_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<SubscriptionRepo>> loadRepos() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_reposKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            SubscriptionRepo.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRepos(List<SubscriptionRepo> repos) async {
    final prefs = await _prefs;
    await prefs.setString(
      _reposKey,
      jsonEncode(repos.map((repo) => repo.toJson()).toList()),
    );
  }

  Future<String?> loadActiveRepoId() async {
    final prefs = await _prefs;
    final value = prefs.getString(_activeRepoKey);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveActiveRepoId(String? repoId) async {
    final prefs = await _prefs;
    if (repoId == null || repoId.isEmpty) {
      await prefs.remove(_activeRepoKey);
    } else {
      await prefs.setString(_activeRepoKey, repoId);
    }
  }

  Future<List<SubscriptionHistoryEntry>> loadHistory() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            SubscriptionHistoryEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHistory(List<SubscriptionHistoryEntry> history) async {
    final prefs = await _prefs;
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((entry) => entry.toJson()).toList()),
    );
  }
}
