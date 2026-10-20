import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_ui.dart';
import 'l10n/l10n.dart';
import 'playback_scaffold.dart';

String legalLocaleTag(Locale locale) {
  final resolved = resolveUiLocale([locale]);
  if (resolved.languageCode == 'zh') {
    return resolved.scriptCode == 'Hant' ? 'zh-Hant' : 'zh-Hans';
  }
  return resolved.languageCode;
}

/// Offline legal text. The loaded Future follows UI locale dependencies, so an
/// already open document changes its body and title together without navigation.
class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({super.key, required this.document});
  final String document;
  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  Future<String>? _content;
  String? _tag;
  Future<String> _load() async {
    final text = await rootBundle.loadString(
      'assets/legal/${widget.document}.$_tag.txt',
    );
    if (text.trim().isEmpty)
      throw const FormatException('empty_legal_document');
    return text;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tag = legalLocaleTag(Localizations.localeOf(context));
    if (_tag != tag) {
      _tag = tag;
      _content = _load();
    }
  }

  @override
  void didUpdateWidget(covariant LegalDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) _content = _load();
  }

  @override
  Widget build(BuildContext context) {
    final privacy = widget.document == 'privacy_policy';
    return PlaybackScaffold(
      appBar: StudyAppBar(
        title: Text(
          privacy
              ? context.tr('隐私政策', '隱私政策', 'Privacy policy', 'プライバシーポリシー')
              : context.tr('内容说明', '內容說明', 'Content information', 'コンテンツについて'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr(
                          '文档暂时无法打开，请重试。',
                          '文件暫時無法開啟，請重試。',
                          'This document is temporarily unavailable. Please try again.',
                          '文書を開けません。もう一度お試しください。',
                        ),
                      ),
                      const SizedBox(height: 12),
                      StudyButton.text(
                        onPressed: () => setState(() => _content = _load()),
                        child: Text(context.tr('重试', '重試', 'Try again', '再試行')),
                      ),
                    ],
                  ),
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      snapshot.data!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        locale: Localizations.localeOf(context),
                        height: 1.7,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
