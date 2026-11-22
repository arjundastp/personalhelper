import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'state.dart';

const seed = Color(0xFF0D74CE);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.init();
  runApp(const RemindlyApp());
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF6F8FB) : scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: b == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: b == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.light ? Colors.white : scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
        home: const HomeScreen(),
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
