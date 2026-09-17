import 'dart:io';

import 'player_memory.dart';

/// 記憶の保存先（端末内のファイル）。保存は書き込み中の落ちに備えて一時ファイル経由。
class PlayerMemoryFile {
  PlayerMemoryFile(this.file);

  final File file;

  PlayerMemory load() {
    try {
      if (file.existsSync()) {
        return PlayerMemory.fromJsonString(file.readAsStringSync(), onChanged: save);
      }
    } on Object {
      // 壊れていたら空から始める（消すより読めない方が困るので黙って作り直す）
    }
    return PlayerMemory(onChanged: save);
  }

  void save(PlayerMemory memory) {
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(memory.toJsonString());
      tmp.renameSync(file.path);
    } on Object {
      // 保存できなくても対局は続ける
    }
  }
}
