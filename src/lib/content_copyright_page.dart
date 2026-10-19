import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_ui.dart';
import 'playback_scaffold.dart';

class ContentCopyrightPage extends StatefulWidget {
  const ContentCopyrightPage({super.key});

  @override
  State<ContentCopyrightPage> createState() => _ContentCopyrightPageState();
}

class _ContentCopyrightPageState extends State<ContentCopyrightPage> {
  late Future<String> _content;

  Future<String> _load() async {
    final text = await rootBundle.loadString('assets/legal/content_copyright.txt');
    if (text.trim().isEmpty) throw const FormatException('内容说明为空');
    return text;
  }

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('内容说明')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('内容说明暂时无法打开，请重试。'),
                const SizedBox(height: 12),
                StudyButton.text(
                  onPressed: () => setState(() => _content = _load()),
                  child: const Text('重试'),
                ),
              ]),
            ));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  snapshot.data!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFamily: 'PingFang SC',
                    locale: const Locale('zh', 'CN'),
                    height: 1.7,
                  ),
                ),
              ),
            )),
          );
        },
      ),
    ),
  );
}
