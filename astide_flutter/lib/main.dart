import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'ui/core/theme/wechat_theme.dart';
import 'ui/features/home/views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: WeuiColors.bg1,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final controller = AppController.createDefault();
  await controller.initialize();

  runApp(AstideApp(controller: controller));
}

/// Root widget for 星汐 Astide.
class AstideApp extends StatefulWidget {
  const AstideApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<AstideApp> createState() => _AstideAppState();
}

class _AstideAppState extends State<AstideApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;
    widget.controller.setAppInBackground(inBackground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        title: '星汐 Astide',
        debugShowCheckedModeBanner: false,
        theme: buildWeuiTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
