import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:provider/provider.dart';
import 'core/locale/locale_controller.dart';
import 'core/theme/theme_controller.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'features/home/presentation/home_screen.dart';

/// 应用根：Material 3 + 莫奈动态色 + Provider 主题状态 + 统一 l10n。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController controller = context.watch<ThemeController>();
    final LocaleController localeController = context.watch<LocaleController>();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'nexhub',
          debugShowCheckedModeBanner: false,
          theme: controller.lightTheme(lightDynamic),
          darkTheme: controller.darkTheme(darkDynamic),
          themeMode: controller.mode,
          locale: localeController.effectiveLocale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[
            Locale('zh'),
            Locale('en'),
          ],
          home: const HomeScreen(),
        );
      },
    );
  }
}
