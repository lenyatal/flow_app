import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

MusicHandler? _audioHandler;
// Глобальная переменная для настроек (для простоты)
bool showBlobs = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _audioHandler = await AudioService.init(
    builder: () => MusicHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.flow.app.audio',
      androidNotificationChannelName: 'Flow Playback',
      androidStopForegroundOnPause: true,
      notificationColor: Colors.deepPurple,
    ),
  );
  runApp(const FlowApp());
}

// --- МОЗГИ (без изменений функционала) ---
class MusicHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  String? clientId;
  List<dynamic> queueList = [];
  List<dynamic> favorites = [];
  Map<String, List<dynamic>> playlists = {};

  MusicHandler() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) skipToNext();
    });
    await _fetchId();
    await _loadStorage();
  }

  Future<void> _fetchId() async {
    try {
      final res = await http
          .get(Uri.parse('https://soundcloud.com'))
          .timeout(const Duration(seconds: 10));
      final urls = RegExp(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"')
          .allMatches(res.body)
          .map((m) => m.group(1))
          .toList();
      for (var url in urls.reversed) {
        final js = await http.get(Uri.parse(url!));
        final m = RegExp(r'client_id:"([a-zA-Z0-9]{32})"').firstMatch(js.body);
        if (m != null) {
          clientId = m.group(1);
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadStorage() async {
    final prefs = await SharedPreferences.getInstance();
    favorites = json.decode(prefs.getString('favs') ?? '[]');
    final plRaw = prefs.getString('playlists') ?? '{}';
    playlists = Map<String, List<dynamic>>.from(
        json.decode(plRaw).map((k, v) => MapEntry(k, List<dynamic>.from(v))));
  }

  Future<void> saveStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('favs', json.encode(favorites));
    await prefs.setString('playlists', json.encode(playlists));
  }

  void toggleFavorite(dynamic t) {
    final isFav = favorites.any((f) => f['id'] == t['id']);
    isFav ? favorites.removeWhere((f) => f['id'] == t['id']) : favorites.add(t);
    saveStorage();
  }

  void insertNext(dynamic track) {
    if (queueList.isEmpty) {
      prepareAndPlay([track], 0);
    } else {
      int curr = queueList
          .indexWhere((t) => t['id'].toString() == mediaItem.value?.id);
      queueList.insert(curr + 1, track);
    }
  }

  Future<void> prepareAndPlay(List<dynamic> list, int index) async {
    queueList = list;
    final track = queueList[index];
    mediaItem.add(MediaItem(
      id: track['id'].toString(),
      album: "Flow",
      title: track['title'],
      artist: track['user']['username'],
      duration: Duration(milliseconds: track['duration']),
      artUri: Uri.parse(
          track['artwork_url']?.toString().replaceAll('large', 't500x500') ??
              ''),
    ));

    try {
      final sUrl =
          "${track['media']['transcodings'][0]['url']}?client_id=$clientId";
      final sRes = await http.get(Uri.parse(sUrl));
      final direct = json.decode(sRes.body)['url'];
      await _player.setUrl(direct);
      _player.play();
    } catch (_) {}
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration pos) => _player.seek(pos);
  @override
  Future<void> skipToNext() async {
    int curr =
        queueList.indexWhere((t) => t['id'].toString() == mediaItem.value?.id);
    if (curr != -1 && curr < queueList.length - 1)
      prepareAndPlay(queueList, curr + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    int curr =
        queueList.indexWhere((t) => t['id'].toString() == mediaItem.value?.id);
    if (curr > 0) prepareAndPlay(queueList, curr - 1);
  }

  PlaybackState _transformEvent(PlaybackEvent event) => PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState:
            AudioProcessingState.values[_player.processingState.index],
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
      );
}

class FlowApp extends StatelessWidget {
  const FlowApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _screenIdx = 1;
  final _search = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;

  Future<void> _doSearch(String q) async {
    setState(() => _loading = true);
    final url = q.isEmpty
        ? 'https://api-v2.soundcloud.com/charts?kind=top&genre=soundcloud%3Agenres%3Aall-music&client_id=${_audioHandler!.clientId}&limit=20'
        : 'https://api-v2.soundcloud.com/search/tracks?q=$q&client_id=${_audioHandler!.clientId}&limit=30';
    try {
      final res = await http.get(Uri.parse(url));
      final data = json.decode(res.body);
      _results = q.isEmpty
          ? (data['collection'] as List).map((e) => e['track']).toList()
          : data['collection'] ?? [];
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _screenIdx,
        onDestinationSelected: (i) => setState(() => _screenIdx = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'Библиотека'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Flow'),
          NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              selectedIcon: Icon(Icons.favorite),
              label: 'Любимое'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Настройки'),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: IndexedStack(
              index: _screenIdx,
              children: [
                _playlistsScreen(),
                _searchView(), // Используем поиск как главный Flow экран
                _favorites(),
                _settingsView(),
              ],
            ),
          ),
          const _M3MiniPlayer(),
        ],
      ),
      // Умная кнопка FAB
      floatingActionButton: _screenIdx == 0
          ? StreamBuilder<MediaItem?>(
              stream: _audioHandler?.mediaItem,
              builder: (context, snap) {
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.only(bottom: snap.data != null ? 85 : 0),
                  child: FloatingActionButton(
                    onPressed: () => _createNewPlaylist(context, setState),
                    child: const Icon(Icons.add),
                  ),
                );
              })
          : null,
    );
  }

  Widget _searchView() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _search,
            hintText: "Поиск треков...",
            onSubmitted: _doSearch,
            leading: const Icon(Icons.search),
            elevation: MaterialStateProperty.all(0),
            backgroundColor: MaterialStateProperty.all(
                Theme.of(context).colorScheme.surfaceVariant),
          ),
        ),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list(_results)),
      ]);

  Widget _playlistsScreen() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Библиотека", style: TextStyle(fontSize: 28))),
          ),
          Expanded(
            child: ListView(
              children: _audioHandler!.playlists.keys
                  .map((name) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.playlist_play),
                        ),
                        title: Text(name),
                        subtitle: Text(
                            "${_audioHandler!.playlists[name]!.length} треков"),
                        onTap: () => setState(() {
                          _results = _audioHandler!.playlists[name]!;
                          _screenIdx = 1;
                        }),
                      ))
                  .toList(),
            ),
          ),
        ],
      );

  Widget _favorites() => Column(children: [
        const Padding(
            padding: EdgeInsets.all(24),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Любимое", style: TextStyle(fontSize: 28)))),
        Expanded(child: _list(_audioHandler!.favorites)),
      ]);

  Widget _settingsView() => Column(
        children: [
          const Padding(
              padding: EdgeInsets.all(24),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Настройки", style: TextStyle(fontSize: 28)))),
          SwitchListTile(
            title: const Text("Анимированные кляксы"),
            subtitle: const Text("Эффекты на фоне плеера"),
            value: showBlobs,
            onChanged: (v) => setState(() => showBlobs = v),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text("Flow 0.4.1",
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.5))),
          ),
        ],
      );

  Widget _list(List<dynamic> tracks) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: tracks.length,
        itemBuilder: (c, i) {
          final t = tracks[i];
          final isFav = _audioHandler!.favorites.any((f) => f['id'] == t['id']);
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                  t['artwork_url']
                          ?.toString()
                          .replaceAll('large', 't500x500') ??
                      '',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note)),
            ),
            title: Text(t['title'] ?? "Untitled",
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(t['user']?['username'] ?? "Unknown"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : null),
                  onPressed: () =>
                      setState(() => _audioHandler!.toggleFavorite(t)),
                ),
                _moreMenu(t),
              ],
            ),
            onTap: () => _audioHandler!.prepareAndPlay(tracks, i),
          );
        },
      );

  Widget _moreMenu(dynamic track) => PopupMenuButton(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (c) => [
          const PopupMenuItem(value: 0, child: Text("Играть следующим")),
          const PopupMenuItem(value: 1, child: Text("Автор")),
          const PopupMenuItem(value: 2, child: Text("Добавить в плейлист")),
        ],
        onSelected: (v) {
          if (v == 0) _audioHandler!.insertNext(track);
          if (v == 1) {
            _search.text = track['user']['username'];
            _doSearch(_search.text);
            setState(() => _screenIdx = 1);
          }
          if (v == 2) _addToPlaylistDialog(context, track);
        },
      );
}

// --- ВИДЖЕТ АНИМИРОВАННЫХ КЛЯКС ---
class BlobBackground extends StatefulWidget {
  const BlobBackground({super.key});
  @override
  State<BlobBackground> createState() => _BlobBackgroundState();
}

class _BlobBackgroundState extends State<BlobBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 15))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showBlobs) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Stack(
        children: [
          _buildBlob(cs.primary.withOpacity(0.15), 150,
              _ctrl.value * 2 * math.pi, 250),
          _buildBlob(cs.tertiary.withOpacity(0.1), -50,
              (_ctrl.value + 0.3) * 2 * math.pi, 300),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double offset, double angle, double size) {
    return Positioned(
      left: offset + (math.sin(angle) * 50),
      top: 100 + (math.cos(angle) * 30),
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

// --- МИНИПЛЕЕР ---
class _M3MiniPlayer extends StatelessWidget {
  const _M3MiniPlayer();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler?.mediaItem,
      builder: (context, snap) {
        if (snap.data == null) return const SizedBox();
        final cs = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(
              onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FullPlayerScreen()),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    height: 68,
                    color: cs.secondaryContainer.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(snap.data!.artUri.toString(),
                                width: 44, height: 44, fit: BoxFit.cover)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(snap.data!.title,
                                maxLines: 1,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                        StreamBuilder<PlaybackState>(
                          stream: _audioHandler?.playbackState,
                          builder: (c, s) => IconButton(
                            icon: Icon(s.data?.playing == true
                                ? Icons.pause
                                : Icons.play_arrow),
                            onPressed: () => s.data?.playing == true
                                ? _audioHandler!.pause()
                                : _audioHandler!.play(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- ФУЛЛПЛЕЕР (С КЛЯКСАМИ И МЕНЮ) ---
class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler?.mediaItem,
      builder: (context, snap) {
        if (snap.data == null) return const SizedBox();
        final item = snap.data!;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Stack(
            children: [
              if (showBlobs) const BlobBackground(),
              Container(color: cs.surface.withOpacity(0.4)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.network(item.artUri.toString(),
                          fit: BoxFit.cover),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(item.artist ?? "",
                                  style: TextStyle(
                                      fontSize: 18, color: cs.onSurfaceVariant),
                                  maxLines: 1),
                            ],
                          ),
                        ),
                        StreamBuilder<MediaItem?>(
                            stream: _audioHandler?.mediaItem,
                            builder: (context, snap) {
                              if (_audioHandler!.queueList.isEmpty)
                                return const SizedBox();
                              final currentTrack = _audioHandler!.queueList
                                  .firstWhere(
                                      (e) => e['id'].toString() == item.id,
                                      orElse: () => null);
                              if (currentTrack == null) return const SizedBox();
                              final isFav = _audioHandler!.favorites
                                  .any((f) => f['id'] == currentTrack['id']);
                              return IconButton(
                                icon: Icon(
                                    isFav
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFav ? Colors.red : null),
                                onPressed: () {
                                  (context as Element).markNeedsBuild();
                                  _audioHandler!.toggleFavorite(currentTrack);
                                },
                              );
                            }),
                        IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showFullMenu(context, item)),
                      ],
                    ),
                    const SizedBox(height: 32),
                    StreamBuilder<Duration>(
                      stream: AudioService.position,
                      builder: (c, s) => Column(children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8)),
                          child: Slider(
                            value: s.data?.inSeconds.toDouble() ?? 0,
                            max: item.duration?.inSeconds.toDouble() ?? 100,
                            onChanged: (v) => _audioHandler!
                                .seek(Duration(seconds: v.toInt())),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_format(s.data ?? Duration.zero)),
                            Text(_format(item.duration ?? Duration.zero)),
                          ],
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 48),
                        IconButton(
                            icon: const Icon(Icons.skip_previous, size: 40),
                            onPressed: () => _audioHandler!.skipToPrevious()),
                        IconButton.filledTonal(
                          iconSize: 48,
                          padding: const EdgeInsets.all(16),
                          icon: StreamBuilder<PlaybackState>(
                            stream: _audioHandler?.playbackState,
                            builder: (c, s) => Icon(s.data?.playing == true
                                ? Icons.pause
                                : Icons.play_arrow),
                          ),
                          onPressed: () =>
                              _audioHandler?.playbackState.value.playing == true
                                  ? _audioHandler!.pause()
                                  : _audioHandler!.play(),
                        ),
                        IconButton(
                            icon: const Icon(Icons.skip_next, size: 40),
                            onPressed: () => _audioHandler!.skipToNext()),
                        IconButton(
                            icon: const Icon(Icons.queue_music, size: 32),
                            onPressed: () => _showQueueDialog(context)),
                      ],
                    ),
                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _format(Duration d) =>
      "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

String _format(Duration d) =>
    "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

// --- ДОП ФУНКЦИИ ---
void _showFullMenu(BuildContext context, MediaItem item) {
  final track =
      _audioHandler!.queueList.firstWhere((e) => e['id'].toString() == item.id);
  showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text("Добавить в плейлист"),
                  onTap: () {
                    Navigator.pop(c);
                    _addToPlaylistDialog(context, track);
                  }),
              ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text("Автор"),
                  onTap: () => Navigator.pop(c)),
            ]),
          ));
}

void _addToPlaylistDialog(BuildContext context, dynamic track) {
  showModalBottomSheet(
      context: context,
      builder: (c) => ListView(
            children: _audioHandler!.playlists.keys
                .map((name) => ListTile(
                      title: Text(name),
                      onTap: () {
                        _audioHandler!.playlists[name]!.add(track);
                        _audioHandler!.saveStorage();
                        Navigator.pop(c);
                      },
                    ))
                .toList(),
          ));
}

void _createNewPlaylist(BuildContext context, Function refresh) {
  final ctrl = TextEditingController();
  showDialog(
      context: context,
      builder: (c) => AlertDialog(
            title: const Text("Новый плейлист"),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text("Отмена")),
              FilledButton(
                  onPressed: () {
                    refresh(() => _audioHandler!.playlists[ctrl.text] = []);
                    Navigator.pop(c);
                  },
                  child: const Text("Огонь")),
            ],
          ));
}

void _showQueueDialog(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  showModalBottomSheet(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Очередь воспроизведения",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: StreamBuilder<MediaItem?>(
                stream: _audioHandler?.mediaItem,
                builder: (context, snap) {
                  final currentId = snap.data?.id;

                  return ListView.builder(
                    itemCount: _audioHandler!.queueList.length,
                    itemBuilder: (context, index) {
                      final track = _audioHandler!.queueList[index];
                      final isCurrent = track['id'].toString() == currentId;

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                              track['artwork_url']
                                      ?.toString()
                                      .replaceAll('large', 't500x500') ??
                                  '',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.music_note)),
                        ),
                        title: Text(track['title'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent ? cs.primary : null)),
                        subtitle: Text(track['user']['username'],
                            style: TextStyle(
                                color: isCurrent
                                    ? cs.primary.withOpacity(0.7)
                                    : null)),
                        onTap: () {
                          _audioHandler!
                              .prepareAndPlay(_audioHandler!.queueList, index);
                          Navigator.pop(context); // Закрыть очередь при тапе
                        },
                      );
                    },
                  );
                }),
          ),
        ],
      ),
    ),
  );
}
