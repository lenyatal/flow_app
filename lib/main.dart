import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

MusicHandler? _audioHandler;
bool showBlobs = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    statusBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _audioHandler = await AudioService.init(
    builder: () => MusicHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.flow.app.audio',
      androidNotificationChannelName: 'Flow Playback',
      androidStopForegroundOnPause: true,
      notificationColor: Colors.white,
    ),
  );
  runApp(const FlowApp());
}

// ─── LIQUID GLASS DESIGN TOKENS ──────────────────────────────────────────────

class LG {
  // Glass surface colors
  static const glassWhite = Color(0x28FFFFFF);
  static const glassWhiteMid = Color(0x18FFFFFF);
  static const glassBorder = Color(0x40FFFFFF);
  static const glassBorderFaint = Color(0x20FFFFFF);
  static const glassHighlight = Color(0x50FFFFFF);

  // Tints for active states
  static const activeTint = Color(0x30FFFFFF);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xAAFFFFFF);
  static const textTertiary = Color(0x66FFFFFF);

  // Background — deep dark
  static const bg = Color(0xFF0A0A0F);
  static const bgLayer = Color(0xFF12121A);

  // Accent — blue like iOS
  static const accent = Color(0xFF3A86FF);
  static const accentSoft = Color(0x403A86FF);
  static const accentGlow = Color(0x203A86FF);

  // Red for favorites
  static const redHeart = Color(0xFFFF3B30);

  // Blur amounts
  static const blurLow = 8.0;
  static const blurMid = 20.0;
  static const blurHigh = 40.0;

  // Border radii
  static const rSmall = 12.0;
  static const rMid = 18.0;
  static const rLarge = 24.0;
  static const rXL = 32.0;
  static const rPill = 100.0;
}

// ─── LIQUID GLASS COMPONENTS ─────────────────────────────────────────────────

/// Core glass container — frosted glass capsule/rect
class GlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final double blur;
  final Color? borderColor;
  final double borderWidth;

  const GlassBox({
    super.key,
    required this.child,
    this.borderRadius = LG.rMid,
    this.padding,
    this.tint,
    this.blur = LG.blurMid,
    this.borderColor,
    this.borderWidth = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint ?? LG.glassWhite,
                tint != null ? tint!.withOpacity(0.08) : LG.glassWhiteMid,
              ],
            ),
            border: Border.all(
              color: borderColor ?? LG.glassBorder,
              width: borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glowing glass button
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? accentColor;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = LG.rPill,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.accentColor,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: GlassBox(
          borderRadius: widget.borderRadius,
          padding: widget.padding,
          tint: widget.accentColor != null
              ? widget.accentColor!.withOpacity(0.2)
              : LG.glassWhite,
          borderColor: widget.accentColor != null
              ? widget.accentColor!.withOpacity(0.5)
              : LG.glassBorder,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Circular glass icon button
class GlassIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? tint;
  final Color? accentColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.tint,
    this.accentColor,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: GlassBox(
          borderRadius: widget.size / 2,
          tint: widget.tint ?? LG.glassWhite,
          borderColor: widget.accentColor?.withOpacity(0.5) ?? LG.glassBorder,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(child: widget.icon),
          ),
        ),
      ),
    );
  }
}

// ─── LIQUID GLASS NAV BAR ─────────────────────────────────────────────────────

class LiquidGlassNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _thumbCtrl;
  late Animation<double> _thumbScale;
  bool _pressing = false;

  // Только основные табы (без поиска)
  final _tabs = const [
    (Icons.library_music_outlined, Icons.library_music, 'Библиотека'),
    (Icons.explore_outlined, Icons.explore, 'Flow'),
    (Icons.favorite_outline, Icons.favorite, 'Любимое'),
    (Icons.settings_outlined, Icons.settings, 'Настройки'),
  ];

  @override
  void initState() {
    super.initState();
    _thumbCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _thumbScale = Tween(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _thumbCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _thumbCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Row(
        children: [
          // Основной pill с табами
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LG.rPill),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(LG.rPill),
                    color: const Color(0x25FFFFFF),
                    border: Border.all(color: LG.glassBorder, width: 0.8),
                  ),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final tabWidth = constraints.maxWidth / _tabs.length;

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Скользящий тумблер
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          left: tabWidth * widget.selectedIndex + 4,
                          top: 4,
                          bottom: 4,
                          width: tabWidth - 8,
                          child: AnimatedBuilder(
                            animation: _thumbScale,
                            builder: (_, child) => Transform.scale(
                              scale: _thumbScale.value,
                              child: child,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(LG.rPill),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: _pressing ? 40 : 20,
                                  sigmaY: _pressing ? 40 : 20,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(LG.rPill),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: _pressing
                                          ? [
                                              const Color(0x55FFFFFF),
                                              const Color(0x30FFFFFF),
                                            ]
                                          : [
                                              const Color(0x40FFFFFF),
                                              const Color(0x20FFFFFF),
                                            ],
                                    ),
                                    border: Border.all(
                                      color: _pressing
                                          ? const Color(0x60FFFFFF)
                                          : const Color(0x35FFFFFF),
                                      width: 0.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withOpacity(_pressing ? 0.3 : 0.2),
                                        blurRadius: _pressing ? 20 : 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Иконки и лейблы
                        Row(
                          children: List.generate(_tabs.length, (i) {
                            final isSelected = i == widget.selectedIndex;
                            final (icon, iconFilled, label) = _tabs[i];
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) {
                                setState(() => _pressing = true);
                                _thumbCtrl.forward();
                                HapticFeedback.selectionClick();
                              },
                              onTapUp: (_) {
                                setState(() => _pressing = false);
                                _thumbCtrl.reverse();
                                widget.onDestinationSelected(i);
                              },
                              onTapCancel: () {
                                setState(() => _pressing = false);
                                _thumbCtrl.reverse();
                              },
                              child: SizedBox(
                                width: tabWidth,
                                height: 62,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isSelected ? iconFilled : icon,
                                      color: isSelected
                                          ? LG.textPrimary
                                          : LG.textSecondary,
                                      size: 22,
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: LG.textPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Отдельная кнопка поиска справа
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onDestinationSelected(1); // Flow/поиск
                },
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x25FFFFFF),
                    border: Border.all(color: LG.glassBorder, width: 0.8),
                  ),
                  child: const Icon(Icons.search_rounded,
                      color: LG.textPrimary, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── МОЗГИ (без изменений) ────────────────────────────────────────────────────

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
      title: track['title'] ?? "Untitled",
      artist: track['user']?['username'] ?? "Unknown",
      duration: Duration(milliseconds: track['duration']),
      artUri: Uri.parse(
          track['artwork_url']?.toString().replaceAll('large', 't500x500') ??
              ''),
    ));

    try {
      var sUrl =
          "${track['media']['transcodings'][0]['url']}?client_id=$clientId";
      var sRes = await http.get(Uri.parse(sUrl));

      if (sRes.statusCode == 401 || sRes.statusCode == 403) {
        await _fetchId();
        sUrl =
            "${track['media']['transcodings'][0]['url']}?client_id=$clientId";
        sRes = await http.get(Uri.parse(sUrl));
      }

      final data = json.decode(sRes.body);
      final directUrl = data['url'];

      await _player.setUrl(directUrl);
      _player.play();
    } catch (e) {
      debugPrint("Ошибка воспроизведения: $e");
    }
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

// ─── APP ──────────────────────────────────────────────────────────────────────

class FlowApp extends StatelessWidget {
  const FlowApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: LG.bg,
        colorScheme: const ColorScheme.dark(
          surface: LG.bg,
          primary: LG.accent,
          secondary: LG.accent,
          onSurface: LG.textPrimary,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: LG.textPrimary),
          bodyMedium: TextStyle(color: LG.textSecondary),
        ),
        iconTheme: const IconThemeData(color: LG.textPrimary),
      ),
      home: const MainNavigation(),
    );
  }
}

// ─── AMBIENT BACKGROUND ───────────────────────────────────────────────────────

class AmbientBackground extends StatefulWidget {
  final String? artworkUrl;
  const AmbientBackground({super.key, this.artworkUrl});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showBlobs)
      return const SizedBox.expand(child: ColoredBox(color: LG.bg));
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * math.pi;
        return Stack(
          children: [
            const SizedBox.expand(child: ColoredBox(color: LG.bg)),
            // Blob 1 — blue accent
            Positioned(
              left: -80 + math.sin(t * 0.7) * 60,
              top: -60 + math.cos(t * 0.5) * 40,
              child: _blob(const Color(0x303A86FF), 320),
            ),
            // Blob 2 — purple
            Positioned(
              right: -100 + math.cos(t * 0.4) * 50,
              bottom: 100 + math.sin(t * 0.6) * 60,
              child: _blob(const Color(0x25BF5AF2), 280),
            ),
            // Blob 3 — cyan subtle
            Positioned(
              left: 80 + math.sin(t * 0.9) * 40,
              bottom: -40 + math.cos(t * 0.8) * 30,
              child: _blob(const Color(0x1830D158), 200),
            ),
          ],
        );
      },
    );
  }

  Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      );
}

// ─── BLOB BACKGROUND (legacy alias) ──────────────────────────────────────────

class BlobBackground extends StatelessWidget {
  const BlobBackground({super.key});
  @override
  Widget build(BuildContext context) => const AmbientBackground();
}

// ─── MAIN NAVIGATION ──────────────────────────────────────────────────────────

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
    return Scaffold(
      backgroundColor: LG.bg,
      extendBody: true,
      body: Stack(
        children: [
          // Ambient background always behind everything
          const AmbientBackground(),
          // Content
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _screenIdx,
              children: [
                _playlistsScreen(),
                _searchView(),
                _favorites(),
                _settingsView(),
              ],
            ),
          ),
          // Mini player
          const _LiquidMiniPlayer(),
        ],
      ),
      floatingActionButton: _screenIdx == 0
          ? StreamBuilder<MediaItem?>(
              stream: _audioHandler?.mediaItem,
              builder: (context, snap) {
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      EdgeInsets.only(bottom: snap.data != null ? 140 : 80),
                  child: GlassButton(
                    onPressed: () => _createNewPlaylist(context, setState),
                    accentColor: LG.accent,
                    padding: const EdgeInsets.all(16),
                    child:
                        const Icon(Icons.add, color: LG.textPrimary, size: 24),
                  ),
                );
              })
          : null,
      bottomNavigationBar: StreamBuilder<MediaItem?>(
        stream: _audioHandler?.mediaItem,
        builder: (_, snap) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (snap.data != null) const _LiquidMiniPlayerPlaceholder(),
              LiquidGlassNavBar(
                selectedIndex: _screenIdx,
                onDestinationSelected: (i) => setState(() => _screenIdx = i),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchView() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _LiquidSearchBar(
              controller: _search,
              onSubmitted: _doSearch,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: _LiquidLoader(),
                  )
                : _list(_results),
          ),
        ],
      );

  Widget _playlistsScreen() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
            child: Text(
              'Библиотека',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: LG.textPrimary,
                letterSpacing: -0.8,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _audioHandler!.playlists.keys
                  .map((name) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LiquidListItem(
                          leading: GlassBox(
                            borderRadius: LG.rSmall,
                            padding: const EdgeInsets.all(12),
                            tint: LG.accentSoft,
                            child: const Icon(Icons.queue_music,
                                color: LG.textPrimary, size: 22),
                          ),
                          title: name,
                          subtitle:
                              '${_audioHandler!.playlists[name]!.length} треков',
                          onTap: () => setState(() {
                            _results = _audioHandler!.playlists[name]!;
                            _screenIdx = 1;
                          }),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      );

  Widget _favorites() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
            child: Text(
              'Любимое',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: LG.textPrimary,
                letterSpacing: -0.8,
              ),
            ),
          ),
          Expanded(child: _list(_audioHandler!.favorites)),
        ],
      );

  Widget _settingsView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
            child: const Text(
              'Настройки',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: LG.textPrimary,
                letterSpacing: -0.8,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassBox(
              borderRadius: LG.rLarge,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Анимированные кляксы',
                            style: TextStyle(
                                color: LG.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: 2),
                        Text('Эффекты на фоне плеера',
                            style: TextStyle(
                                color: LG.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  _LiquidSwitch(
                    value: showBlobs,
                    onChanged: (v) => setState(() => showBlobs = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassBox(
              borderRadius: LG.rLarge,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('отключить Liquid Glass',
                            style: TextStyle(
                                color: LG.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: 2),
                        Text('Убирает blur эффекты',
                            style: TextStyle(
                                color: LG.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  _LiquidSwitch(
                    value: !showBlobs,
                    onChanged: (v) => setState(() => showBlobs = !v),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: Text(
                'Flow 0.4.1',
                style: const TextStyle(color: LG.textTertiary, fontSize: 14),
              ),
            ),
          ),
        ],
      );

  Widget _list(List<dynamic> tracks) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
        itemCount: tracks.length,
        itemBuilder: (c, i) {
          final t = tracks[i];
          final isFav = _audioHandler!.favorites.any((f) => f['id'] == t['id']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LiquidTrackTile(
              track: t,
              isFav: isFav,
              onTap: () => _audioHandler!.prepareAndPlay(tracks, i),
              onFavTap: () => setState(() => _audioHandler!.toggleFavorite(t)),
              moreMenu: _moreMenu(t),
            ),
          );
        },
      );

  Widget _moreMenu(dynamic track) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) => _LiquidBottomSheet(
              children: [
                _LiquidSheetItem(
                  icon: Icons.skip_next_rounded,
                  label: 'Играть следующим',
                  onTap: () {
                    _audioHandler!.insertNext(track);
                    Navigator.pop(context);
                  },
                ),
                _LiquidSheetItem(
                  icon: Icons.person_rounded,
                  label: 'Автор',
                  onTap: () {
                    _search.text = track['user']['username'];
                    _doSearch(_search.text);
                    setState(() => _screenIdx = 1);
                    Navigator.pop(context);
                  },
                ),
                _LiquidSheetItem(
                  icon: Icons.playlist_add_rounded,
                  label: 'Добавить в плейлист',
                  onTap: () {
                    Navigator.pop(context);
                    _addToPlaylistDialog(context, track);
                  },
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.more_horiz_rounded,
            color: LG.textSecondary, size: 20),
      );
}

// ─── LIQUID TRACK TILE ────────────────────────────────────────────────────────

class _LiquidTrackTile extends StatelessWidget {
  final dynamic track;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onFavTap;
  final Widget moreMenu;

  const _LiquidTrackTile({
    required this.track,
    required this.isFav,
    required this.onTap,
    required this.onFavTap,
    required this.moreMenu,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassBox(
        borderRadius: LG.rLarge,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(LG.rSmall),
              child: Image.network(
                track['artwork_url']
                        ?.toString()
                        .replaceAll('large', 't500x500') ??
                    '',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: LG.glassWhiteMid,
                    borderRadius: BorderRadius.circular(LG.rSmall),
                  ),
                  child: const Icon(Icons.music_note, color: LG.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track['title'] ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LG.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track['user']?['username'] ?? 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: LG.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onFavTap();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFav ? LG.redHeart : LG.textTertiary,
                  size: 20,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: moreMenu,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LIQUID LIST ITEM (плейлисты) ────────────────────────────────────────────

class _LiquidListItem extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LiquidListItem({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassBox(
        borderRadius: LG.rLarge,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: LG.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: LG.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: LG.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── LIQUID SEARCH BAR ────────────────────────────────────────────────────────

class _LiquidSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _LiquidSearchBar({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      borderRadius: LG.rPill,
      blur: LG.blurMid,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: LG.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: LG.textPrimary, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Поиск треков...',
                hintStyle: TextStyle(color: LG.textTertiary, fontSize: 16),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: LG.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LIQUID LOADER ────────────────────────────────────────────────────────────

class _LiquidLoader extends StatefulWidget {
  const _LiquidLoader();
  @override
  State<_LiquidLoader> createState() => _LiquidLoaderState();
}

class _LiquidLoaderState extends State<_LiquidLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassBox(
        borderRadius: LG.rPill,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 24,
          height: 24,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CircularProgressIndicator(
              value: null,
              strokeWidth: 2.5,
              color: LG.accent,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── LIQUID SWITCH ────────────────────────────────────────────────────────────

class _LiquidSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LiquidSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 50,
        height: 28,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LG.rPill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: LG.blurMid, sigmaY: LG.blurMid),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LG.rPill),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: value
                      ? [
                          const Color(0xFF34C759),
                          const Color(0xFF2AA147),
                        ]
                      : [
                          LG.glassWhiteMid,
                          LG.glassWhite,
                        ],
                ),
                border: Border.all(
                    color: value ? const Color(0x6034C759) : LG.glassBorder,
                    width: 0.8),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: value ? 24 : 2,
                    top: 2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── LIQUID MINI PLAYER ───────────────────────────────────────────────────────

class _LiquidMiniPlayerPlaceholder extends StatelessWidget {
  const _LiquidMiniPlayerPlaceholder();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 80);
}

class _LiquidMiniPlayer extends StatelessWidget {
  const _LiquidMiniPlayer();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler?.mediaItem,
      builder: (context, snap) {
        if (snap.data == null) return const SizedBox();
        final item = snap.data!;

        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FullPlayerScreen(),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(LG.rXL),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(LG.rXL),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x35FFFFFF),
                          Color(0x15FFFFFF),
                        ],
                      ),
                      border: Border.all(color: LG.glassBorder, width: 0.8),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        // Artwork
                        ClipRRect(
                          borderRadius: BorderRadius.circular(LG.rSmall),
                          child: Image.network(
                            item.artUri.toString(),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 50,
                              height: 50,
                              color: LG.glassWhiteMid,
                              child: const Icon(Icons.music_note,
                                  color: LG.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: LG.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Text(
                                item.artist ?? '',
                                maxLines: 1,
                                style: const TextStyle(
                                    color: LG.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Controls
                        StreamBuilder<PlaybackState>(
                          stream: _audioHandler?.playbackState,
                          builder: (_, s) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GlassIconButton(
                                size: 40,
                                icon: Icon(
                                  s.data?.playing == true
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: LG.textPrimary,
                                  size: 22,
                                ),
                                onPressed: () => s.data?.playing == true
                                    ? _audioHandler!.pause()
                                    : _audioHandler!.play(),
                              ),
                              const SizedBox(width: 6),
                              GlassIconButton(
                                size: 40,
                                icon: const Icon(Icons.skip_next_rounded,
                                    color: LG.textPrimary, size: 20),
                                onPressed: () => _audioHandler!.skipToNext(),
                              ),
                            ],
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

// ─── FULL PLAYER SCREEN ───────────────────────────────────────────────────────

class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return StreamBuilder<MediaItem?>(
      stream: _audioHandler?.mediaItem,
      builder: (context, snap) {
        if (snap.data == null) return const SizedBox();
        final item = snap.data!;

        return Container(
          height: screenH * 0.92,
          decoration: const BoxDecoration(
            color: LG.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(LG.rXL)),
          ),
          child: Stack(
            children: [
              // Background
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(LG.rXL)),
                child: const AmbientBackground(),
              ),
              // Frosted overlay
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(LG.rXL)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Container(
                    color: LG.bg.withOpacity(0.6),
                  ),
                ),
              ),
              // Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      // Handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: LG.glassBorder,
                            borderRadius: BorderRadius.circular(LG.rPill),
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                      // Artwork — big with glass frame
                      _ArtworkHero(artUri: item.artUri.toString()),
                      const Spacer(flex: 2),
                      // Track info + controls
                      _TrackInfo(item: item),
                      const SizedBox(height: 28),
                      // Seek slider
                      _LiquidSeekBar(item: item),
                      const SizedBox(height: 32),
                      // Playback controls
                      _PlaybackControls(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── ARTWORK HERO ─────────────────────────────────────────────────────────────

class _ArtworkHero extends StatelessWidget {
  final String artUri;
  const _ArtworkHero({required this.artUri});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width - 56;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LG.rXL),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: LG.accent.withOpacity(0.15),
            blurRadius: 60,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LG.rXL),
        child: Stack(
          children: [
            Image.network(
              artUri,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: LG.glassWhiteMid,
                child: const Center(
                    child: Icon(Icons.music_note,
                        size: 64, color: LG.textSecondary)),
              ),
            ),
            // Glass gloss overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size * 0.4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── TRACK INFO ───────────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  final MediaItem item;
  const _TrackInfo({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  color: LG.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                item.artist ?? '',
                style: const TextStyle(color: LG.textSecondary, fontSize: 17),
                maxLines: 1,
              ),
            ],
          ),
        ),
        // Fav button
        StreamBuilder<MediaItem?>(
          stream: _audioHandler?.mediaItem,
          builder: (context, snap) {
            if (_audioHandler!.queueList.isEmpty) return const SizedBox();
            final currentTrack = _audioHandler!.queueList.firstWhere(
                (e) => e['id'].toString() == item.id,
                orElse: () => null);
            if (currentTrack == null) return const SizedBox();
            final isFav = _audioHandler!.favorites
                .any((f) => f['id'] == currentTrack['id']);
            return GlassIconButton(
              size: 44,
              tint: isFav ? LG.redHeart.withOpacity(0.2) : LG.glassWhite,
              accentColor: isFav ? LG.redHeart : null,
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? LG.redHeart : LG.textSecondary,
                size: 22,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                (context as Element).markNeedsBuild();
                _audioHandler!.toggleFavorite(currentTrack);
              },
            );
          },
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          size: 44,
          icon: const Icon(Icons.more_horiz_rounded,
              color: LG.textSecondary, size: 22),
          onPressed: () => _showFullMenu(context, item),
        ),
      ],
    );
  }
}

// ─── LIQUID SEEK BAR ──────────────────────────────────────────────────────────

class _LiquidSeekBar extends StatelessWidget {
  final MediaItem item;
  const _LiquidSeekBar({required this.item});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.position,
      builder: (c, s) {
        final pos = s.data ?? Duration.zero;
        final dur = item.duration ?? Duration.zero;
        final progress = dur.inMilliseconds > 0
            ? pos.inMilliseconds / dur.inMilliseconds
            : 0.0;

        return Column(
          children: [
            // Custom glass track
            GestureDetector(
              onHorizontalDragUpdate: (d) {
                final box = c.findRenderObject() as RenderBox;
                final localPos = box.globalToLocal(d.globalPosition);
                final ratio = (localPos.dx / box.size.width).clamp(0.0, 1.0);
                _audioHandler!.seek(Duration(
                    milliseconds: (ratio * dur.inMilliseconds).toInt()));
              },
              onTapUp: (d) {
                final box = c.findRenderObject() as RenderBox;
                final localPos = box.globalToLocal(d.globalPosition);
                final ratio = (localPos.dx / box.size.width).clamp(0.0, 1.0);
                _audioHandler!.seek(Duration(
                    milliseconds: (ratio * dur.inMilliseconds).toInt()));
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Track
                    ClipRRect(
                      borderRadius: BorderRadius.circular(LG.rPill),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0x40FFFFFF),
                            borderRadius: BorderRadius.circular(LG.rPill),
                          ),
                        ),
                      ),
                    ),
                    // Progress fill
                    LayoutBuilder(builder: (_, constraints) {
                      return Container(
                        height: 6,
                        width: constraints.maxWidth * progress,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(LG.rPill),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3A86FF), Color(0xFFBF5AF2)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: LG.accent.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Thumb
                    LayoutBuilder(builder: (_, constraints) {
                      return Positioned(
                        left: (constraints.maxWidth * progress - 10)
                            .clamp(0.0, constraints.maxWidth - 20),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: LG.accent.withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(pos),
                    style:
                        const TextStyle(color: LG.textTertiary, fontSize: 12)),
                Text(_format(dur),
                    style:
                        const TextStyle(color: LG.textTertiary, fontSize: 12)),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── PLAYBACK CONTROLS ────────────────────────────────────────────────────────

class _PlaybackControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GlassIconButton(
          size: 52,
          icon: const Icon(Icons.skip_previous_rounded,
              color: LG.textPrimary, size: 28),
          onPressed: () {
            HapticFeedback.selectionClick();
            _audioHandler!.skipToPrevious();
          },
        ),
        // Main play/pause — larger, accent tinted
        StreamBuilder<PlaybackState>(
          stream: _audioHandler?.playbackState,
          builder: (_, s) {
            final playing = s.data?.playing == true;
            return GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                playing ? _audioHandler!.pause() : _audioHandler!.play();
              },
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x503A86FF),
                          Color(0x30BF5AF2),
                        ],
                      ),
                      border: Border.all(
                          color: LG.accent.withOpacity(0.5), width: 0.8),
                    ),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: LG.textPrimary,
                      size: 36,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        GlassIconButton(
          size: 52,
          icon: const Icon(Icons.skip_next_rounded,
              color: LG.textPrimary, size: 28),
          onPressed: () {
            HapticFeedback.selectionClick();
            _audioHandler!.skipToNext();
          },
        ),
        GlassIconButton(
          size: 52,
          icon: const Icon(Icons.queue_music_rounded,
              color: LG.textSecondary, size: 22),
          onPressed: () => _showQueueDialog(context),
        ),
      ],
    );
  }
}

// ─── LIQUID BOTTOM SHEET ──────────────────────────────────────────────────────

class _LiquidBottomSheet extends StatelessWidget {
  final List<Widget> children;
  const _LiquidBottomSheet({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 32),
      child: GlassBox(
        borderRadius: LG.rXL,
        blur: LG.blurHigh,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: LG.glassBorder,
                    borderRadius: BorderRadius.circular(LG.rPill)),
              ),
              const SizedBox(height: 8),
              ...children,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidSheetItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LiquidSheetItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GlassBox(
        borderRadius: LG.rSmall,
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: LG.textPrimary, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              color: LG.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

// ─── ДОП ФУНКЦИИ (без изменений логики) ──────────────────────────────────────

String _format(Duration d) =>
    "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

void _showFullMenu(BuildContext context, MediaItem item) {
  final track =
      _audioHandler!.queueList.firstWhere((e) => e['id'].toString() == item.id);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) => _LiquidBottomSheet(
      children: [
        _LiquidSheetItem(
          icon: Icons.playlist_add_rounded,
          label: 'Добавить в плейлист',
          onTap: () {
            Navigator.pop(c);
            _addToPlaylistDialog(context, track);
          },
        ),
        _LiquidSheetItem(
          icon: Icons.person_rounded,
          label: 'Автор',
          onTap: () => Navigator.pop(c),
        ),
      ],
    ),
  );
}

void _addToPlaylistDialog(BuildContext context, dynamic track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) => _LiquidBottomSheet(
      children: _audioHandler!.playlists.keys
          .map((name) => _LiquidSheetItem(
                icon: Icons.queue_music_rounded,
                label: name,
                onTap: () {
                  _audioHandler!.playlists[name]!.add(track);
                  _audioHandler!.saveStorage();
                  Navigator.pop(c);
                },
              ))
          .toList(),
    ),
  );
}

void _createNewPlaylist(BuildContext context, Function refresh) {
  final ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (c) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: AlertDialog(
        backgroundColor: LG.bgLayer,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(LG.rXL)),
        title: const Text('Новый плейлист',
            style: TextStyle(color: LG.textPrimary)),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(LG.rMid),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: LG.glassWhite,
                borderRadius: BorderRadius.circular(LG.rMid),
                border: Border.all(color: LG.glassBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: LG.textPrimary),
                cursorColor: LG.accent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Название...',
                  hintStyle: TextStyle(color: LG.textTertiary),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child:
                const Text('Отмена', style: TextStyle(color: LG.textSecondary)),
          ),
          GlassButton(
            onPressed: () {
              refresh(() => _audioHandler!.playlists[ctrl.text] = []);
              Navigator.pop(c);
            },
            accentColor: LG.accent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: const Text('Готово',
                style: TextStyle(
                    color: LG.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

void _showQueueDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: GlassBox(
          borderRadius: LG.rXL,
          blur: LG.blurHigh,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: LG.glassBorder,
                    borderRadius: BorderRadius.circular(LG.rPill)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Очередь',
                    style: TextStyle(
                      color: LG.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: _audioHandler?.mediaItem,
                  builder: (context, snap) {
                    final currentId = snap.data?.id;
                    return ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: _audioHandler!.queueList.length,
                      itemBuilder: (context, index) {
                        final track = _audioHandler!.queueList[index];
                        final isCurrent = track['id'].toString() == currentId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            onTap: () {
                              _audioHandler!.prepareAndPlay(
                                  _audioHandler!.queueList, index);
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(LG.rMid),
                                gradient: isCurrent
                                    ? LinearGradient(
                                        colors: [
                                          LG.accent.withOpacity(0.25),
                                          LG.accentGlow,
                                        ],
                                      )
                                    : null,
                                border: isCurrent
                                    ? Border.all(
                                        color: LG.accent.withOpacity(0.4),
                                        width: 0.8)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(LG.rSmall),
                                    child: Image.network(
                                      track['artwork_url']
                                              ?.toString()
                                              .replaceAll(
                                                  'large', 't500x500') ??
                                          '',
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.music_note),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track['title'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isCurrent
                                                ? LG.accent
                                                : LG.textPrimary,
                                            fontWeight: isCurrent
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          track['user']['username'],
                                          style: TextStyle(
                                            color: isCurrent
                                                ? LG.accent.withOpacity(0.7)
                                                : LG.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    const Icon(Icons.equalizer_rounded,
                                        color: LG.accent, size: 18),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
