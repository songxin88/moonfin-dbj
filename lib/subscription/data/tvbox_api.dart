/// 订阅源（TVBox / 饭太硬 JSON 配置）的 HTTP API 与解析逻辑。
///
/// 这里只依赖 `http` 和 `dart:convert`，不依赖 Moonfin 的 server_core /
/// playback_core，方便订阅源模块独立维护，也方便后续合并官方 main 分支。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/subscription_models.dart';

class TvboxException implements Exception {
  TvboxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次“线路 -> 可播放地址”的解析结果。
class ResolvedPlayUrl {
  const ResolvedPlayUrl(this.url, {this.parsedBy = ''});

  final String url;

  /// 解析接口名称，直链时为空。
  final String parsedBy;
}

class TvboxApi {
  TvboxApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  static const _mediaExtension = {
    'm3u8',
    'mp4',
    'mkv',
    'avi',
    'flv',
    'ts',
    'm4v',
    'mov',
    'wmv',
    'webm',
    'rmvb',
    'mp3',
    'm4a',
    'aac',
    'flac',
  };

  // ---------------------------------------------------------------------------
  // 配置加载
  // ---------------------------------------------------------------------------

  /// 读取一个订阅配置。支持 http(s) 地址，也支持直接粘贴 JSON 文本。
  ///
  /// 多仓配置会返回 [SubscriptionConfig.depots]，调用方需要再选择一条线路，
  /// 并用 [fetchConfig] 读取所选线路的地址。
  Future<SubscriptionConfig> fetchConfig(
    String source, {
    Map<String, String> headers = const {},
  }) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw TvboxException('订阅地址不能为空');
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _parseConfig(trimmed);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      throw TvboxException('订阅地址格式不正确：$trimmed');
    }

    final response = await _get(
      trimmed,
      headers: {
        'Accept': 'application/json, text/plain, */*',
        ...headers,
      },
    );
    return _parseConfig(_decodeBody(response));
  }

  SubscriptionConfig _parseConfig(String raw) {
    final text = _maybeDecodeBase64(_stripBom(raw).trim());
    if (text.isEmpty) {
      throw TvboxException('订阅内容为空');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw TvboxException('订阅内容不是合法的 JSON 配置');
    }

    if (decoded is! Map) {
      throw TvboxException('订阅配置必须是 JSON 对象');
    }
    return SubscriptionConfig.fromJson(Map<String, dynamic>.from(decoded));
  }

  // ---------------------------------------------------------------------------
  // 浏览接口
  // ---------------------------------------------------------------------------

  /// 首页/最新列表。JSON 接口先用 `ac=list`，失败或没有内容时退回
  /// `ac=detail`；XML 接口使用 `ac=videolist`。
  Future<VodPage> home(
    SubscriptionSite site, {
    int page = 1,
    Map<String, String> headers = const {},
  }) async {
    if (site.isXmlApi) {
      return _xmlPage(site, page: page, headers: headers);
    }
    final body = await _requestJson(
      site,
      {
        'ac': page <= 1 ? 'list' : 'detail',
        'pg': '$page',
      },
      headers: headers,
    );
    final parsed = _jsonPage(body, page: page);
    if (parsed.items.isEmpty && page <= 1) {
      final fallback = await _requestJson(
        site,
        {'ac': 'detail', 'pg': '1'},
        headers: headers,
      );
      return _jsonPage(fallback, page: 1);
    }
    return parsed;
  }

  /// 分类列表。[categoryId] 为空时等同于首页。
  Future<VodPage> category(
    SubscriptionSite site, {
    required String categoryId,
    int page = 1,
    Map<String, String> headers = const {},
  }) async {
    if (site.isXmlApi) {
      return _xmlPage(
        site,
        page: page,
        categoryId: categoryId,
        headers: headers,
      );
    }
    final body = await _requestJson(
      site,
      {
        'ac': 'detail',
        't': categoryId,
        'pg': '$page',
        if (site.ext.isNotEmpty) 'ext': site.ext,
      },
      headers: headers,
    );
    return _jsonPage(body, page: page);
  }

  /// 搜索。
  Future<VodPage> search(
    SubscriptionSite site,
    String keyword, {
    int page = 1,
    Map<String, String> headers = const {},
  }) async {
    final word = keyword.trim();
    if (word.isEmpty) return const VodPage();
    if (site.isXmlApi) {
      return _xmlPage(
        site,
        page: page,
        keyword: word,
        headers: headers,
      );
    }
    final body = await _requestJson(
      site,
      {
        'ac': 'detail',
        'wd': word,
        'pg': '$page',
        if (site.ext.isNotEmpty) 'ext': site.ext,
      },
      headers: headers,
    );
    return _jsonPage(body, page: page);
  }

  /// 详情。JSON 接口的 `ac=detail&ids=` 会返回 `list` 数组。
  Future<Vod> detail(
    SubscriptionSite site,
    String vodId, {
    Map<String, String> headers = const {},
  }) async {
    if (site.isXmlApi) {
      final page = await _xmlPage(
        site,
        page: 1,
        ids: vodId,
        headers: headers,
      );
      if (page.items.isEmpty) {
        throw TvboxException('没有找到影片详情：$vodId');
      }
      return page.items.first;
    }

    final body = await _requestJson(
      site,
      {'ac': 'detail', 'ids': vodId},
      headers: headers,
    );
    final page = _jsonPage(body, page: 1);
    if (page.items.isEmpty) {
      throw TvboxException('没有找到影片详情：$vodId');
    }
    return page.items.first;
  }

  // ---------------------------------------------------------------------------
  // 播放地址解析
  // ---------------------------------------------------------------------------

  /// 把 `vod_play_url` 里的一集地址解析成可以直接交给播放器的地址。
  ///
  /// - 直链（m3u8/mp4/...）原样返回；
  /// - `xx://` 之类的站内协议交给配置里的 `parses` 解析接口；
  /// - 解析不了时抛出 [TvboxException]，由界面提示用户。
  Future<ResolvedPlayUrl> resolvePlayUrl({
    required String rawUrl,
    required SubscriptionSite site,
    required String sourceName,
    required List<SubscriptionParse> parses,
  }) async {
    final cleaned = _unwrapEpisodeUrl(rawUrl);
    if (cleaned.isEmpty) {
      throw TvboxException('这一集没有播放地址');
    }

    final uri = Uri.tryParse(cleaned);
    final scheme = uri?.scheme.toLowerCase() ?? '';

    if (scheme == 'http' || scheme == 'https') {
      if (_isDirectMedia(cleaned)) {
        return ResolvedPlayUrl(cleaned);
      }
      final parsed = await _tryParse(cleaned, site, sourceName, parses);
      if (parsed != null) return parsed;
      // 有些接口会直接返回带鉴权参数的播放地址，没有扩展名也交给播放器试一次。
      return ResolvedPlayUrl(cleaned);
    }

    if (scheme == 'magnet' ||
        scheme == 'ed2k' ||
        scheme == 'thunder' ||
        scheme == 'ftp') {
      throw TvboxException('该地址需要下载器（$scheme），暂不支持直接播放');
    }

    if (scheme.isEmpty && cleaned.startsWith('/')) {
      final base = Uri.tryParse(site.api);
      if (base != null && base.hasScheme) {
        final absolute = base.resolve(cleaned).toString();
        if (_isDirectMedia(absolute)) return ResolvedPlayUrl(absolute);
      }
    }

    final parsed = await _tryParse(cleaned, site, sourceName, parses);
    if (parsed != null) return parsed;

    final label = sourceName.isNotEmpty ? sourceName : site.name;
    throw TvboxException(
      '“$label”线路需要在外部解析器中播放（${cleaned.split(':').first}），'
      '当前订阅源播放器暂不支持，请换一条线路。',
    );
  }

  /// 只做同步判断：这一集的地址是否可以直接播放。用于历史记录/UI 预览。
  bool canPlayDirectly(String rawUrl) {
    final cleaned = _unwrapEpisodeUrl(rawUrl);
    final uri = Uri.tryParse(cleaned);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    return (scheme == 'http' || scheme == 'https') &&
        _isDirectMedia(cleaned);
  }

  String _unwrapEpisodeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          for (final key in const ['url', 'playUrl', 'link', 'src']) {
            final candidate = _asString(map[key]).trim();
            if (candidate.isNotEmpty) return candidate;
          }
        }
      } catch (_) {}
    }
    // TVBox 的地址偶尔会带 `#` 之类的请求头后缀，这里只取真正的 URL 部分。
    if (value.startsWith('http')) {
      final hash = value.indexOf('#');
      if (hash > 0 && value.substring(hash + 1).contains('=')) {
        value = value.substring(0, hash);
      }
    }
    return value;
  }

  bool _isDirectMedia(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    final extension = path.substring(dot + 1);
    return _mediaExtension.contains(extension);
  }

  Future<ResolvedPlayUrl?> _tryParse(
    String rawUrl,
    SubscriptionSite site,
    String sourceName,
    List<SubscriptionParse> parses,
  ) async {
    SubscriptionParse? match;
    for (final parse in parses) {
      if (parse.url.isEmpty) continue;
      if (parse.flags.any(
        (flag) =>
            flag.trim() == sourceName ||
            flag.trim() == site.name ||
            flag.trim() == site.key,
      )) {
        match = parse;
        break;
      }
    }
    // 没有配置 flag 的解析接口，TVBox 也不会给这个线路使用。
    if (match == null) return null;
    // type 0/1 是 JSON 解析接口；type 2/3 需要 WebView/嗅探内核。
    if (match.type > 1) return null;

    final endpoint = match.url.trim();
    if (endpoint.isEmpty) return null;

    final getUrl = _buildParseUrl(endpoint, rawUrl);
    try {
      final response = await _get(
        getUrl,
        headers: {'Accept': 'application/json, text/plain, */*'},
      );
      final direct = _extractParsedUrl(_decodeBody(response));
      if (direct != null) {
        return ResolvedPlayUrl(direct, parsedBy: match.name);
      }
    } catch (_) {}

    // 部分解析接口只接受 POST。
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'User-Agent': _defaultUserAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'url': rawUrl},
          )
          .timeout(const Duration(seconds: 15));
      final direct = _extractParsedUrl(_decodeBody(response));
      if (direct != null) {
        return ResolvedPlayUrl(direct, parsedBy: match.name);
      }
    } catch (_) {}

    return null;
  }

  String _buildParseUrl(String endpoint, String rawUrl) {
    final encoded = Uri.encodeComponent(rawUrl);
    if (endpoint.contains('{url}')) {
      return endpoint.replaceAll('{url}', encoded);
    }
    if (endpoint.endsWith('=') || endpoint.endsWith('?') || endpoint.endsWith('&')) {
      return '$endpoint$encoded';
    }
    return _withParams(endpoint, {'url': rawUrl});
  }

  String? _extractParsedUrl(String body) {
    final text = body.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      final found = _findUrlInJson(decoded);
      if (found != null) return found;
    } catch (_) {}
    if (text.startsWith('http') && !text.contains('<')) {
      return text;
    }
    return null;
  }

  String? _findUrlInJson(dynamic value, [int depth = 0]) {
    if (depth > 4) return null;
    if (value is String) {
      if (value.startsWith('http') && !value.contains('<')) return value;
      return null;
    }
    if (value is List) {
      for (final item in value) {
        final found = _findUrlInJson(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (value is Map) {
      for (final key in const ['url', 'playUrl', 'play_url', 'src', 'data']) {
        if (!value.containsKey(key)) continue;
        final found = _findUrlInJson(value[key], depth + 1);
        if (found != null) return found;
      }
      for (final entry in value.entries) {
        if (entry.key is! String) continue;
        final found = _findUrlInJson(entry.value, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HTTP / JSON / XML 解析细节
  // ---------------------------------------------------------------------------

  Future<String> _requestJson(
    SubscriptionSite site,
    Map<String, String> params, {
    Map<String, String> headers = const {},
  }) async {
    final url = _withParams(site.api, params);
    final response = await _get(url, headers: {
      ...site.header,
      ...headers,
    });
    return _decodeBody(response);
  }

  /// 给已有查询参数的接口追加参数，例如 `api.php/provide/vod/?ac=list`。
  String _withParams(String api, Map<String, String> params) {
    final uri = Uri.tryParse(api);
    if (uri == null) {
      final separator = api.contains('?') ? '&' : '?';
      return '$api$separator${Uri(queryParameters: params).query}';
    }
    final merged = <String, String>{...uri.queryParameters, ...params};
    return uri.replace(queryParameters: merged).toString();
  }

  Future<http.Response> _get(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (url.trim().isEmpty) {
      throw TvboxException('接口地址为空');
    }
    try {
      final response = await _client
          .get(
            Uri.parse(url.trim()),
            headers: {
              'User-Agent': _defaultUserAgent,
              ...headers,
            },
          )
          .timeout(timeout);
      if (response.statusCode >= 400) {
        throw TvboxException('接口返回 HTTP ${response.statusCode}');
      }
      return response;
    } on TvboxException {
      rethrow;
    } on TimeoutException {
      throw TvboxException('请求超时：$url');
    } catch (error) {
      throw TvboxException('网络请求失败：$error');
    }
  }

  String _decodeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return latin1.decode(response.bodyBytes);
    }
  }

  String _stripBom(String text) =>
      text.startsWith('\ufeff') ? text.substring(1) : text;

  String _maybeDecodeBase64(String text) {
    if (text.contains('{')) return text;
    final compact = text.replaceAll(RegExp(r'\s'), '');
    if (compact.length < 16 ||
        !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(compact)) {
      return text;
    }
    try {
      final decoded = utf8.decode(base64.decode(compact));
      return decoded.contains('{') ? decoded : text;
    } catch (_) {
      return text;
    }
  }

  VodPage _jsonPage(String body, {required int page}) {
    final map = _decodeJsonMap(body);
    final categories = <VodCategory>[];
    final rawClasses = map['class'] ?? map['classes'] ?? map['category'];
    if (rawClasses is List) {
      for (final item in rawClasses) {
        if (item is! Map) continue;
        final entry = Map<String, dynamic>.from(item);
        final id = _asString(entry['type_id'] ?? entry['id']).trim();
        final name = _asString(entry['type_name'] ?? entry['name']).trim();
        if (id.isEmpty || name.isEmpty) continue;
        categories.add(VodCategory(id: id, name: name));
      }
    }

    final items = <Vod>[];
    final rawList = map['list'] ?? map['data'] ?? map['videos'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is! Map) continue;
        final vod = _jsonVod(Map<String, dynamic>.from(item));
        if (vod.id.isEmpty || vod.name.isEmpty) continue;
        items.add(vod);
      }
    } else if (rawList is Map) {
      final vod = _jsonVod(Map<String, dynamic>.from(rawList));
      if (vod.id.isNotEmpty && vod.name.isNotEmpty) items.add(vod);
    }

    final currentPage = _asInt(map['page'], page);
    final pageCount = _asInt(map['pagecount'] ?? map['page_count'], page);
    final total = _asInt(map['total']);
    return VodPage(
      categories: categories,
      items: items,
      page: currentPage <= 0 ? page : currentPage,
      pageCount: pageCount <= 0 ? page : pageCount,
      total: total,
    );
  }

  Vod _jsonVod(Map<String, dynamic> item) {
    final playFrom = _asString(item['vod_play_from']);
    final playUrl = _asString(item['vod_play_url']);
    return Vod(
      id: _asString(item['vod_id'] ?? item['id']).trim(),
      name: _asString(item['vod_name'] ?? item['name']).trim(),
      pic: _asString(item['vod_pic'] ?? item['pic']).trim(),
      remarks: _asString(item['vod_remarks'] ?? item['note']).trim(),
      year: _asString(item['vod_year'] ?? item['year']).trim(),
      area: _asString(item['vod_area'] ?? item['area']).trim(),
      language: _asString(item['vod_lang'] ?? item['lang']).trim(),
      typeName: _asString(
        item['type_name'] ?? item['vod_class'] ?? item['class'],
      ).trim(),
      score: _asString(item['vod_score'] ?? item['score']).trim(),
      actor: _asString(item['vod_actor'] ?? item['actor']).trim(),
      director: _asString(item['vod_director'] ?? item['director']).trim(),
      content: _asString(item['vod_content'] ?? item['des'] ?? item['content'])
          .trim(),
      sources: _parsePlaySources(playFrom, playUrl),
    );
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final text = _stripBom(body).trim();
    if (text.isEmpty) {
      throw TvboxException('接口没有返回内容');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw TvboxException('接口返回的不是 JSON（该站点可能不是 JSON 接口）');
    }
    if (decoded is List) return {'list': decoded};
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw TvboxException('接口返回的 JSON 格式无法识别');
  }

  Future<VodPage> _xmlPage(
    SubscriptionSite site, {
    required int page,
    String? categoryId,
    String? keyword,
    String? ids,
    Map<String, String> headers = const {},
  }) async {
    final url = _withParams(site.api, {
      'ac': 'videolist',
      if (categoryId != null && categoryId.isNotEmpty) 't': categoryId,
      if (keyword != null && keyword.isNotEmpty) 'wd': keyword,
      if (ids != null && ids.isNotEmpty) 'ids': ids,
      'pg': '$page',
    });
    final response = await _get(url, headers: {
      ...site.header,
      ...headers,
    });
    return _parseXmlPage(_decodeBody(response), fallbackPage: page);
  }

  VodPage _parseXmlPage(String body, {required int fallbackPage}) {
    final categories = <VodCategory>[];
    final classPattern = RegExp(
      r'<ty[^>]*id="([^"]*)"[^>]*>([\s\S]*?)</ty>',
      caseSensitive: false,
    );
    for (final match in classPattern.allMatches(body)) {
      final id = (match.group(1) ?? '').trim();
      final name = _xmlText(match.group(2) ?? '');
      if (id.isEmpty || name.isEmpty) continue;
      categories.add(VodCategory(id: id, name: name));
    }

    var page = fallbackPage;
    var pageCount = fallbackPage;
    final listTag = RegExp(r'<list([^>]*)>', caseSensitive: false).firstMatch(body);
    if (listTag != null) {
      final attrs = listTag.group(1) ?? '';
      page = _xmlAttribute(attrs, 'page') ?? page;
      pageCount = _xmlAttribute(attrs, 'pagecount') ?? pageCount;
    }

    final items = <Vod>[];
    final videoPattern = RegExp(
      r'<video>([\s\S]*?)</video>',
      caseSensitive: false,
    );
    for (final match in videoPattern.allMatches(body)) {
      final block = match.group(1) ?? '';
      final id = _xmlTag(block, 'id');
      final name = _xmlTag(block, 'name');
      if (id.isEmpty || name.isEmpty) continue;
      final playFrom = _xmlTag(block, 'vod_play_from');
      final playUrl = _xmlTag(block, 'vod_play_url');
      items.add(
        Vod(
          id: id,
          name: name,
          pic: _xmlTag(block, 'pic'),
          remarks: _xmlTag(block, 'note'),
          year: _xmlTag(block, 'year'),
          area: _xmlTag(block, 'area'),
          language: _xmlTag(block, 'lang'),
          typeName: _xmlTag(block, 'type'),
          score: _xmlTag(block, 'score'),
          actor: _xmlTag(block, 'actor'),
          director: _xmlTag(block, 'director'),
          content: _xmlTag(block, 'des'),
          sources: _parsePlaySources(playFrom, playUrl),
        ),
      );
    }

    return VodPage(
      categories: categories,
      items: items,
      page: page,
      pageCount: pageCount,
      total: items.length,
    );
  }

  int? _xmlAttribute(String attrs, String name) {
    final match = RegExp('$name="([^"]*)"').firstMatch(attrs);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  String _xmlTag(String block, String tag) {
    final match = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    if (match == null) return '';
    return _xmlText(match.group(1) ?? '');
  }

  String _xmlText(String raw) {
    var text = raw.trim();
    if (text.startsWith('<![CDATA[')) {
      text = text.substring(9);
      if (text.endsWith(']]>')) {
        text = text.substring(0, text.length - 3);
      }
    }
    return _unescapeXml(text).trim();
  }

  String _unescapeXml(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');

  // ---------------------------------------------------------------------------
  // 播放地址分组：vod_play_from / vod_play_url 使用 $$$ 与 # 分隔
  // ---------------------------------------------------------------------------

  List<VodPlaySource> _parsePlaySources(String playFrom, String playUrl) {
    if (playUrl.trim().isEmpty) return const [];
    final groups = playUrl.split(r'$$$');
    final names = playFrom.split(r'$$$');
    final sources = <VodPlaySource>[];
    for (var index = 0; index < groups.length; index++) {
      final episodes = _parseEpisodes(groups[index]);
      if (episodes.isEmpty) continue;
      var name = index < names.length ? names[index].trim() : '';
      if (name.isEmpty) name = '线路${sources.length + 1}';
      sources.add(VodPlaySource(name: name, episodes: episodes));
    }
    return sources;
  }

  List<VodEpisode> _parseEpisodes(String group) {
    final episodes = <VodEpisode>[];
    for (final raw in group.split('#')) {
      final piece = raw.trim();
      if (piece.isEmpty) continue;
      final separator = piece.lastIndexOf(r'$');
      var name = '';
      var url = piece;
      if (separator >= 0) {
        name = piece.substring(0, separator).trim();
        url = piece.substring(separator + 1).trim();
      }
      if (url.isEmpty) continue;
      if (name.isEmpty) name = '第${episodes.length + 1}集';
      episodes.add(VodEpisode(name: name, url: url));
    }
    return episodes;
  }

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
}
