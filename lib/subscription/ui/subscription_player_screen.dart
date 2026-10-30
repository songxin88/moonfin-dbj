import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../models/subscription_models.dart';
import '../state/subscription_controller.dart';

/// 订阅源播放器。
///
/// 视频固定使用 `BoxFit.contain` 居中显示，不拉伸、不裁切。
class SubscriptionPlayerScreen extends StatefulWidget {
  const SubscriptionPlayerScreen({
    super.key,
    required this.title,
    required this.playlist,
    required this.initialIndex,
    this.pic = '',
    this.vodId = '',
    this.siteKey = '',
    this.sourceName = '',
    this.repoId = '',
    this.initialUrl,
  });

  final String title;
  final String pic;
  final String vodId;
  final String siteKey;
  final String sourceName;
  final String repoId;
  final List<VodEpisode> playlist;
  final int initialIndex;

  /// 详情页已经解析好的首个地址，避免重复请求解析接口。
  final String? initialUrl;

  @override
  State<SubscriptionPlayerScreen> createState() =>
      _SubscriptionPlayerScreenState();
}

class _SubscriptionPlayerScreenState extends State<SubscriptionPlayerScreen> {
  final _controller = SubscriptionController.instance;

  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Timer? _progressTimer;
  Timer? _hideTimer;

  int _index = 0;
  String _resolvedUrl = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _ready = false;
  bool _controlsVisible = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _index = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _player = Player();
    _videoController = VideoController(_player);
    _bindStreams();
    if (widget.playlist.isEmpty) {
      _error = '没有可播放的剧集';
      _opening = false;
    } else {
      _openCurrent(useInitialUrl: true);
    }
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveHistory(),
    );
  }

  void _bindStreams() {
    _subscriptions
      ..add(
        _player.stream.position.listen((position) {
          if (!mounted) return;
          setState(() => _position = position);
        }),
      )
      ..add(
        _player.stream.duration.listen((duration) {
          if (!mounted) return;
          setState(() => _duration = duration);
        }),
      )
      ..add(
        _player.stream.playing.listen((playing) {
          if (!mounted) return;
          setState(() => _playing = playing);
          if (playing) _scheduleHideControls();
        }),
      )
      ..add(
        _player.stream.buffering.listen((buffering) {
          if (!mounted) return;
          setState(() => _buffering = buffering);
        }),
      )
      ..add(
        _player.stream.completed.listen((completed) {
          if (!mounted || !completed) return;
          _saveHistory();
          if (_index + 1 < widget.playlist.length) {
            _openAt(_index + 1);
          }
        }),
      )
      ..add(
        _player.stream.error.listen((error) {
          if (!mounted) return;
          setState(() {
            _error = error;
            _ready = false;
          });
        }),
      );
  }

  Future<void> _openCurrent({bool useInitialUrl = false}) async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _ready = false;
      _opening = true;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      String url;
      if (useInitialUrl &&
          widget.initialUrl != null &&
          widget.initialUrl!.isNotEmpty) {
        url = widget.initialUrl!;
      } else {
        url = await _resolveUrl(widget.playlist[_index].url);
      }
      if (!mounted) return;
      _resolvedUrl = url;
      await _player.open(Media(url), play: true);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _opening = false;
      });
      _scheduleHideControls();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _opening = false;
      });
    }
  }

  Future<String> _resolveUrl(String rawUrl) async {
    final repo = _repo;
    final site = _site;
    if (repo != null && site != null) {
      final resolved = await _controller.resolvePlayUrl(
        repo: repo,
        site: site,
        sourceName: widget.sourceName,
        rawUrl: rawUrl,
      );
      return resolved.url;
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    throw Exception('缺少站点信息，无法解析这个播放地址');
  }

  SubscriptionRepo? get _repo {
    for (final repo in _controller.repos) {
      if (repo.id == widget.repoId) return repo;
    }
    return _controller.activeRepo;
  }

  SubscriptionSite? get _site {
    final repo = _repo;
    if (repo == null) return null;
    return _controller.siteOf(repo, widget.siteKey);
  }

  VodEpisode? get _episode {
    if (_index < 0 || _index >= widget.playlist.length) return null;
    return widget.playlist[_index];
  }

  Future<void> _openAt(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    await _saveHistory();
    if (!mounted) return;
    setState(() => _index = index);
    await _openCurrent();
  }

  Future<void> _saveHistory() async {
    if (widget.vodId.isEmpty || _resolvedUrl.isEmpty) return;
    final episode = _episode;
    if (episode == null) return;
    try {
      await _controller.upsertHistory(
        repoId: widget.repoId,
        siteKey: widget.siteKey,
        vodId: widget.vodId,
        name: widget.title,
        pic: widget.pic,
        sourceName: widget.sourceName,
        episodeName: episode.name,
        episodeUrl: _resolvedUrl,
        position: _position,
        duration: _duration,
      );
    } catch (_) {}
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _saveHistory();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _videoController,
            controls: NoVideoControls,
            fit: BoxFit.contain,
            fill: Colors.black,
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
            ),
          ),
          if (_opening || (!_ready && _error == null))
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (_buffering && _ready && _error == null)
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (_error != null) _buildError(),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _buildControls(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 42),
          const SizedBox(height: AppSpacing.spaceMd),
          const Text(
            '播放失败',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: AppSpacing.spaceSm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.spaceLg),
          FilledButton(
            onPressed: () => _openCurrent(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final episode = _episode;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + AppSpacing.spaceSm,
              left: AppSpacing.spaceSm,
              right: AppSpacing.spaceLg,
              bottom: AppSpacing.space2xl,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: Colors.white,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTypography.fontSizeMd,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (episode != null)
                        Text(
                          episode.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: AppTypography.fontSizeXs,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '选集',
                  onPressed: _showEpisodes,
                  icon: const Icon(Icons.playlist_play_rounded),
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            onTap: () {
              _player.playOrPause();
              _scheduleHideControls();
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: AppSpacing.spaceMd,
              right: AppSpacing.spaceMd,
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.spaceSm,
              top: AppSpacing.space2xl,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColorScheme.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColorScheme.accent,
                  ),
                  child: Slider(
                    max: _duration.inMilliseconds <= 0
                        ? 1
                        : _duration.inMilliseconds.toDouble(),
                    value: _position.inMilliseconds
                        .clamp(0, _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds)
                        .toDouble(),
                    onChanged: (value) {
                      setState(
                        () => _position = Duration(
                          milliseconds: value.round(),
                        ),
                      );
                    },
                    onChangeEnd: (value) {
                      _player.seek(Duration(milliseconds: value.round()));
                      _scheduleHideControls();
                    },
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _format(_position),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: AppTypography.fontSizeXs,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '/',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: AppTypography.fontSizeXs,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _format(_duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: AppTypography.fontSizeXs,
                      ),
                    ),
                    const Spacer(),
                    if (_index + 1 < widget.playlist.length)
                      TextButton.icon(
                        onPressed: () => _openAt(_index + 1),
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          size: 18,
                        ),
                        label: const Text('下一集'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showEpisodes() {
    if (widget.playlist.isEmpty) return;
    showModalBottomSheet<void>(
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
                0,
                AppSpacing.spaceLg,
                AppSpacing.spaceSm,
              ),
              child: Text(
                '选集 · ${widget.playlist.length} 集',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.playlist.length,
                itemBuilder: (context, index) {
                  final episode = widget.playlist[index];
                  final selected = index == _index;
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.play_circle_fill_rounded
                          : Icons.play_circle_outline_rounded,
                      color: selected
                          ? AppColorScheme.accent
                          : AppColorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    title: Text(episode.name),
                    selected: selected,
                    onTap: () {
                      Navigator.of(context).pop();
                      _openAt(index);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.spaceSm),
          ],
        ),
      ),
    );
  }

  String _format(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
