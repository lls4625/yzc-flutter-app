import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_ui.dart';
import 'playback_scaffold.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late Future<String> _content;

  Future<String> _load() async {
    final text = await rootBundle.loadString('assets/legal/privacy_policy.txt');
    if (text.trim().isEmpty) throw const FormatException('隐私政策内容为空');
    return text;
  }

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('隐私政策')),
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
                const Text('隐私政策暂时无法打开，请重试。'),
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'), height: 1.7),
                ),
              ),
            )),
          );
        },
      ),
    ),
  );
}
