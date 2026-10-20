import 'dart:async';

import 'l10n/l10n.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data.dart';
import 'resources.dart';
import 'resource_operation_coordinator.dart';
import 'ui.dart';
import 'system_errors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    SystemErrors.record(
      details.exception,
      details.stack ?? StackTrace.current,
      module: 'flutter',
      operation: '框架异常',
      context: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (_) => Directionality(
    textDirection: TextDirection.ltr,
    child: Builder(
      builder: (context) => Center(
        child: Text(
          localizedText(
            Localizations.maybeLocaleOf(context) ??
                resolveUiLocale(PlatformDispatcher.instance.locales),
            '页面显示异常，请重新进入',
            '頁面顯示異常，請重新進入',
            'Could not display this page. Please reopen it.',
            'ページを表示できませんでした。開き直してください。',
          ),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    ),
  );
  PlatformDispatcher.instance.onError = (error, stack) {
    SystemErrors.record(error, stack, module: 'runtime', operation: '未捕获异步异常');
    return true;
  };
  try {
    await initializeStudyGlass();
    final store = AppStore();
    await store.open();
    unawaited(SystemErrors.pruneOnLogin());
    final resourceOperations = ResourceOperationCoordinator();
    final resources = Resources(store, operations: resourceOperations);
    await resources.recover();
    final controller = AppController(store, resources, resourceOperations);
    await controller.studyResources.initialize();
    await controller.reload();
    runApp(studyGlassRoot(StudyApp(controller)));
  } catch (error, stack) {
    SystemErrors.record(
      error,
      stack,
      module: 'startup',
      operation: '初始化应用',
      hint: '本地数据暂时无法打开',
    );
    await SystemErrors.flush();
    runApp(
      studyGlassRoot(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          supportedLocales: supportedUiLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeListResolutionCallback: (locales, _) =>
              resolveUiLocale(locales),
          theme: studyTheme(Brightness.light),
          darkTheme: studyTheme(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.storage_outlined, size: 56),
                      const SizedBox(height: 20),
                      Text(
                        context.l10n.startupError,
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 12),
                      Text(context.l10n.startupHint),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
