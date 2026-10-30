/// 订阅源模块的纯数据模型。
///
/// 这里刻意不依赖 Moonfin 的 server_core / playback_core，
/// 让订阅源可以作为独立模块维护，方便后续与 Moonfin 官方 main 分支合并。
library;

String _asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

/// 一条“仓库/多仓”线路。饭太硬多仓配置形如：
/// `{"urls":[{"name":"线路一","url":"http://..."}]}`
class SubscriptionDepot {
  final String name;
  final String url;

  const SubscriptionDepot({required this.name, required this.url});

  factory SubscriptionDepot.fromJson(Map<String, dynamic> json) {
    return SubscriptionDepot(
      name: _asString(json['name'], '未命名线路'),
      url: _asString(json['url']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

/// TVBox 配置里的一个点播站点（`sites` 数组的一项）。
///
/// `type` 的含义沿用 TVBox：
/// 0 = XML 接口，1 = JSON 接口，3 = JS/Python/PHP/JAR 爬虫，4 = 带 extend 的 JSON 接口。
class SubscriptionSite {
  final String key;
  final String name;
  final int type;
  final String api;
  final String ext;
  final String playerUrl;
  final int searchable;
  final int quickSearch;
  final Map<String, String> header;
  final List<String> categories;
  final String icon;

  const SubscriptionSite({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.ext = '',
    this.playerUrl = '',
    this.searchable = 1,
    this.quickSearch = 1,
    this.header = const {},
    this.categories = const [],
    this.icon = '',
  });

  factory SubscriptionSite.fromJson(Map<String, dynamic> json) {
    final key = _asString(json['key']).trim();
    final api = _asString(json['api']).trim();
    var type = _asInt(json['type'], -1);
    if (type < 0) {
      if (api.startsWith('csp_') ||
          api.endsWith('.js') ||
          api.endsWith('.py') ||
          api.endsWith('.php')) {
        type = 3;
      } else if (api.contains('api.php') || api.contains('/provide/vod')) {
        type = 1;
      } else {
        type = 1;
      }
    }
    final headerJson = json['header'];
    final header = <String, String>{};
    if (headerJson is Map) {
      headerJson.forEach((k, v) => header[_asString(k)] = _asString(v));
    }
    final categories = <String>[];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final c in rawCategories) {
        final value = _asString(c).trim();
        if (value.isNotEmpty) categories.add(value);
      }
    }
    return SubscriptionSite(
      key: key,
      name: _asString(json['name'], key),
      type: type,
      api: api,
      ext: _asString(json['ext']),
      playerUrl: _asString(json['playerUrl']),
      searchable: _asInt(json['searchable'], 1),
      quickSearch: _asInt(json['quickSearch'], 1),
      header: header,
      categories: categories,
      icon: _asString(json['icon']),
    );
  }

  bool get isJsonApi => type == 1 || type == 4;
  bool get isXmlApi => type == 0;
  bool get isSpider => type == 3;

  /// 当前纯 Dart 内核能够直接访问的类型。
  bool get isSupported => isJsonApi || isXmlApi;

  String get unsupportedReason {
    if (!isSupported) {
      return '该站点使用 JS/Python/PHP/JAR 爬虫（${api.isEmpty ? 'csp_' : api}），'
          '需要 TVBox 原生解析内核，当前纯 Dart 订阅源模块暂不支持。';
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'type': type,
    'api': api,
    'ext': ext,
    'playerUrl': playerUrl,
    'searchable': searchable,
    'quickSearch': quickSearch,
    'header': header,
    'categories': categories,
    'icon': icon,
  };
}

/// 配置里的解析接口（`parses`）。
class SubscriptionParse {
  final String name;
  final int type;
  final String url;
  final String ext;
  final List<String> flags;

  const SubscriptionParse({
    required this.name,
    required this.type,
    required this.url,
    this.ext = '',
    this.flags = const [],
  });

  factory SubscriptionParse.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['flag'];
    final flags = <String>[];
    if (rawFlags is List) {
      for (final f in rawFlags) {
        final value = _asString(f).trim();
        if (value.isNotEmpty) flags.add(value);
      }
    } else {
      final value = _asString(rawFlags).trim();
      if (value.isNotEmpty) {
        flags.addAll(value.split(',').where((e) => e.trim().isNotEmpty));
      }
    }
    return SubscriptionParse(
      name: _asString(json['name'], '解析'),
      type: _asInt(json['type'], 1),
      url: _asString(json['url']),
      ext: _asString(json['ext']),
      flags: flags,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'url': url,
    'ext': ext,
    'flag': flags,
  };
}

/// 解析后的整份 TVBox / 饭太硬配置。
class SubscriptionConfig {
  final List<SubscriptionDepot> depots;
  final List<SubscriptionSite> sites;
  final List<SubscriptionParse> parses;
  final String spider;

  const SubscriptionConfig({
    this.depots = const [],
    this.sites = const [],
    this.parses = const [],
    this.spider = '',
  });

  bool get isMultiRepo => depots.isNotEmpty && sites.isEmpty;

  factory SubscriptionConfig.fromJson(Map<String, dynamic> json) {
    final depots = <SubscriptionDepot>[];
    final rawUrls = json['urls'];
    if (rawUrls is List) {
      for (final item in rawUrls) {
        if (item is Map) {
          depots.add(
            SubscriptionDepot.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final sites = <SubscriptionSite>[];
    final rawSites = json['sites'];
    if (rawSites is List) {
      for (final item in rawSites) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final site = SubscriptionSite.fromJson(map);
          // 和原版 ConfigParser 一致：缺少 key/api 的站点直接跳过。
          if (site.key.isEmpty || site.api.isEmpty) continue;
          sites.add(site);
        }
      }
    }

    final parses = <SubscriptionParse>[];
    final rawParses = json['parses'];
    if (rawParses is List) {
      for (final item in rawParses) {
        if (item is Map) {
          parses.add(
            SubscriptionParse.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return SubscriptionConfig(
      depots: depots,
      sites: sites,
      parses: parses,
      spider: _asString(json['spider']),
    );
  }
}

/// 一个点播条目的基本信息。列表页和详情页共用。
class Vod {
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String year;
  final String area;
  final String language;
  final String typeName;
  final String score;
  final String actor;
  final String director;
  final String content;
  final List<VodPlaySource> sources;

  const Vod({
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.language = '',
    this.typeName = '',
    this.score = '',
    this.actor = '',
    this.director = '',
    this.content = '',
    this.sources = const [],
  });

  String get displayRemarks => remarks.isNotEmpty ? remarks : year;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pic': pic,
    'remarks': remarks,
    'year': year,
    'area': area,
    'language': language,
    'typeName': typeName,
    'score': score,
    'actor': actor,
    'director': director,
    'content': content,
  };

  factory Vod.fromJson(Map<String, dynamic> json) => Vod(
    id: _asString(json['id']),
    name: _asString(json['name']),
    pic: _asString(json['pic']),
    remarks: _asString(json['remarks']),
    year: _asString(json['year']),
    area: _asString(json['area']),
    language: _asString(json['language']),
    typeName: _asString(json['typeName']),
    score: _asString(json['score']),
    actor: _asString(json['actor']),
    director: _asString(json['director']),
    content: _asString(json['content']),
  );
}

/// 一条播放线路（`vod_play_from` 的一项），对应一组选集。
class VodPlaySource {
  final String name;
  final List<VodEpisode> episodes;

  const VodPlaySource({required this.name, required this.episodes});

  bool get isEmpty => episodes.isEmpty;

  VodPlaySource copyWith({String? name, List<VodEpisode>? episodes}) {
    return VodPlaySource(
      name: name ?? this.name,
      episodes: episodes ?? this.episodes,
    );
  }
}

/// 一集。
class VodEpisode {
  final String name;
  final String url;

  const VodEpisode({required this.name, required this.url});
}

/// 一个分类（TVBox 配置里的 `class` 字段）。
class VodCategory {
  final String id;
  final String name;

  const VodCategory({required this.id, required this.name});
}

/// 一次列表请求的结果。
class VodPage {
  final List<VodCategory> categories;
  final List<Vod> items;
  final int page;
  final int pageCount;
  final int total;

  const VodPage({
    this.categories = const [],
    this.items = const [],
    this.page = 1,
    this.pageCount = 1,
    this.total = 0,
  });

  bool get hasMore => page < pageCount;
}

/// 订阅仓库（用户在 App 里添加的一条 JSON 订阅地址）。
class SubscriptionRepo {
  final String id;
  final String name;
  final String url;
  final bool isMultiRepo;
  final List<SubscriptionDepot> depots;
  final String selectedDepotUrl;
  final List<SubscriptionSite> sites;
  final List<SubscriptionParse> parses;
  final String spider;
  final DateTime updatedAt;

  const SubscriptionRepo({
    required this.id,
    required this.name,
    required this.url,
    this.isMultiRepo = false,
    this.depots = const [],
    this.selectedDepotUrl = '',
    this.sites = const [],
    this.parses = const [],
    this.spider = '',
    required this.updatedAt,
  });

  SubscriptionRepo copyWith({
    String? name,
    String? url,
    bool? isMultiRepo,
    List<SubscriptionDepot>? depots,
    String? selectedDepotUrl,
    List<SubscriptionSite>? sites,
    List<SubscriptionParse>? parses,
    String? spider,
    DateTime? updatedAt,
  }) {
    return SubscriptionRepo(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      isMultiRepo: isMultiRepo ?? this.isMultiRepo,
      depots: depots ?? this.depots,
      selectedDepotUrl: selectedDepotUrl ?? this.selectedDepotUrl,
      sites: sites ?? this.sites,
      parses: parses ?? this.parses,
      spider: spider ?? this.spider,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SubscriptionRepo.fromJson(Map<String, dynamic> json) {
    final depots = <SubscriptionDepot>[];
    final rawDepots = json['depots'];
    if (rawDepots is List) {
      for (final item in rawDepots) {
        if (item is Map) {
          depots.add(SubscriptionDepot.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final sites = <SubscriptionSite>[];
    final rawSites = json['sites'];
    if (rawSites is List) {
      for (final item in rawSites) {
        if (item is Map) {
          sites.add(SubscriptionSite.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final parses = <SubscriptionParse>[];
    final rawParses = json['parses'];
    if (rawParses is List) {
      for (final item in rawParses) {
        if (item is Map) {
          parses.add(
            SubscriptionParse.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return SubscriptionRepo(
      id: _asString(json['id']),
      name: _asString(json['name'], '订阅源'),
      url: _asString(json['url']),
      isMultiRepo: json['isMultiRepo'] == true,
      depots: depots,
      selectedDepotUrl: _asString(json['selectedDepotUrl']),
      sites: sites,
      parses: parses,
      spider: _asString(json['spider']),
      updatedAt: DateTime.tryParse(_asString(json['updatedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'isMultiRepo': isMultiRepo,
    'depots': depots.map((e) => e.toJson()).toList(),
    'selectedDepotUrl': selectedDepotUrl,
    'sites': sites.map((e) => e.toJson()).toList(),
    'parses': parses.map((e) => e.toJson()).toList(),
    'spider': spider,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// 本地播放历史，只属于订阅源模块，不写入 Moonfin 的媒体库历史。
class SubscriptionHistoryEntry {
  final String repoId;
  final String siteKey;
  final String vodId;
  final String name;
  final String pic;
  final String sourceName;
  final String episodeName;
  final String episodeUrl;
  final Duration position;
  final Duration duration;
  final DateTime viewedAt;

  const SubscriptionHistoryEntry({
    required this.repoId,
    required this.siteKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.sourceName = '',
    this.episodeName = '',
    this.episodeUrl = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    required this.viewedAt,
  });

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }

  factory SubscriptionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistoryEntry(
      repoId: _asString(json['repoId']),
      siteKey: _asString(json['siteKey']),
      vodId: _asString(json['vodId']),
      name: _asString(json['name']),
      pic: _asString(json['pic']),
      sourceName: _asString(json['sourceName']),
      episodeName: _asString(json['episodeName']),
      episodeUrl: _asString(json['episodeUrl']),
      position: Duration(seconds: _asInt(json['position'])),
      duration: Duration(seconds: _asInt(json['duration'])),
      viewedAt: DateTime.tryParse(_asString(json['viewedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'repoId': repoId,
    'siteKey': siteKey,
    'vodId': vodId,
    'name': name,
    'pic': pic,
    'sourceName': sourceName,
    'episodeName': episodeName,
    'episodeUrl': episodeUrl,
    'position': position.inSeconds,
    'duration': duration.inSeconds,
    'viewedAt': viewedAt.toIso8601String(),
  };
}
