import 'package:flutter/material.dart';

import 'legal_document_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const LegalDocumentPage(document: 'privacy_policy');
}
