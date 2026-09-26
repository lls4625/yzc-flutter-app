import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app.dart';
import 'data.dart';
import 'resources.dart';
import 'ui.dart';
import 'system_errors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    SystemErrors.record(details.exception, details.stack ?? StackTrace.current,
      module: 'flutter', operation: '框架异常',
      context: {'library': details.library, 'context': details.context?.toDescription()});
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (_) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('页面显示异常，请重新进入', style: TextStyle(fontSize: 16))),
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
    final resources = Resources(store);
    await resources.recover();
    final controller = AppController(store, resources);
    await controller.studyResources.initialize();
    await controller.reload();
    runApp(studyGlassRoot(StudyApp(controller)));
  } catch (error, stack) {
    SystemErrors.record(error, stack, module: 'startup', operation: '初始化应用', hint: '本地数据暂时无法打开');
    await SystemErrors.flush();
    runApp(studyGlassRoot(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: studyTheme(Brightness.light),
      darkTheme: studyTheme(Brightness.dark),
      home: Scaffold(body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.storage_outlined, size: 56),
        const SizedBox(height: 20),
        const Text('本地数据暂时无法打开', style: TextStyle(fontSize: 22)),
        const SizedBox(height: 12),
        const Text('请重新打开 APP。已有数据库不会自动删除或重建。'),
      ]),
    ))))));
  }
}
