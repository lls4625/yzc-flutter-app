typedef ListeningDemoRow = Map<String, Object?>;

String listeningDemoText(ListeningDemoRow row, String key) =>
    row[key]?.toString() ?? '';

enum ListeningDemoKind {
  words('单词'), content('课文');
  const ListeningDemoKind(this.label);
  final String label;
}

enum ListeningDemoStage { selection, player }

class ListeningDemoClip {
  const ListeningDemoClip(this.kind, this.row, this.path);
  final ListeningDemoKind kind;
  final ListeningDemoRow row;
  final String path;
  String get id => '${kind.name}:${row['id']}';
  Map<String, Object?> get request => {'id': id, 'path': path};
}
