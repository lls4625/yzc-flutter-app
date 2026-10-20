import 'package:flutter/material.dart';

import 'legal_document_page.dart';

class ContentCopyrightPage extends StatelessWidget {
  const ContentCopyrightPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const LegalDocumentPage(document: 'content_copyright');
}
