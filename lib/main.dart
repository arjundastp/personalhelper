import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/shell.dart';
import 'state.dart';

/// Colours modelled on the messaging apps most people already use every day:
/// a green top bar, white list, and green round buttons.
class AppColors {
  static const green = Color(0xFF008069); // top bar (light)
  static const accent = Color(0xFF00A884); // buttons, switches, highlights
  static const darkBg = Color(0xFF111B21);
  static const darkBar = Color(0xFF202C33);
  static const grey = Color(0xFF667781);
  static const red = Color(0xFFEA0038);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.init();
  runApp(const RemindlyApp());
}

ThemeData buildTheme(Brightness b, {String? fontFamily}) {
  final light = b == Brightness.light;
  final base = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: b);
  final scheme = base.copyWith(
    primary: light ? AppColors.green : AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    surface: light ? Colors.white : AppColors.darkBg,
    onSurfaceVariant: light ? AppColors.grey : const Color(0xFF8696A0),
    outlineVariant: light ? const Color(0xFFE9EDEF) : const Color(0xFF222D34),
    error: AppColors.red,
  );
  return ThemeData(
    fontFamily: fontFamily,
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? AppColors.green : AppColors.darkBar,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600),
      iconTheme: const IconThemeData(color: Colors.white, size: 26),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 26),
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: light ? AppColors.green : AppColors.darkBar,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      extendedTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : scheme.onSurfaceVariant),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, color: scheme.onSurfaceVariant),
      iconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      minVerticalPadding: 12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: scheme.outlineVariant, width: 2)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent.withValues(alpha: 0.5), width: 2)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent, width: 2)),
      floatingLabelStyle: TextStyle(fontFamily: fontFamily, color: AppColors.accent),
      hintStyle: TextStyle(fontFamily: fontFamily, color: scheme.onSurfaceVariant),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.accent, selectionHandleColor: AppColors.accent),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: light ? Colors.white : AppColors.darkBg,
        minimumSize: const Size(64, 52),
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: light ? AppColors.green : AppColors.accent,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: light ? AppColors.green : AppColors.accent,
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, color: scheme.onSurface),
      selectedColor: AppColors.accent.withValues(alpha: light ? 0.15 : 0.3),
      checkmarkColor: light ? AppColors.green : AppColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: const Color(0xCCFFFFFF),
      indicatorColor: Colors.white,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: light ? Colors.white : AppColors.darkBar,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: light ? const Color(0xFFD9FDD3) : const Color(0xFF103529),
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 13.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: scheme.onSurface,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? (light ? const Color(0xFF005C4B) : AppColors.accent) : scheme.onSurfaceVariant,
          )),
    ),
    badgeTheme: BadgeThemeData(backgroundColor: AppColors.accent, textColor: Colors.white, textStyle: TextStyle(fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w700)),
    dialogTheme: DialogThemeData(backgroundColor: light ? Colors.white : AppColors.darkBar),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class RemindlyApp extends StatelessWidget {
  const RemindlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Remindly',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: state.themeMode,
        builder: (context, child) {
          final large = state.setting('largeText', false);
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: large ? mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.2)) : mq,
            child: AppLockGate(child: child!),
          );
        },
        home: const Shell(),
      ),
    );
  }
}

/// Asks for fingerprint / face / phone PIN when "App lock" is on. The alert screen never asks,
/// so a ringing reminder can always be dismissed.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const relockAfter = Duration(seconds: 30);
  final _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _authenticating = false;
  DateTime? _pausedAt;

  bool get _lockOn => AppState.instance.setting('appLock', false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_lockOn) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_authenticating) return; // the system prompt itself pauses/resumes the app
    if (s == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      AppState.instance.refresh();
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (_lockOn && _unlocked && away > relockAfter) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    bool ok = false;
    try {
      final supported = await _auth.isDeviceSupported();
      ok = !supported || // no lock configured on the phone: nothing to check against
          await _auth.authenticate(localizedReason: 'Unlock Remindly', persistAcrossBackgrounding: true);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _unlocked = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_lockOn || _unlocked) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded, size: 56, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 28),
              Text('Remindly is locked', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Use your fingerprint, face or phone screen lock to open.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 28),
                  label: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Used by Settings before turning the lock on, so nobody locks themselves out.
Future<bool> confirmDeviceAuth() async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return false;
    return await auth.authenticate(localizedReason: 'Confirm to turn on app lock');
  } catch (_) {
    return false;
  }
}
