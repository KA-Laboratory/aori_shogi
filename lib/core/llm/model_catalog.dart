/// 端末内LLMのモデル一覧。ここは純粋なデータなので、プラグイン無しでも読める（テストもできる）。
///
/// 形式は `.litertlm`（LiteRT-LM）。配布はアプリ内ダウンロードで、端末に保存される。
/// 出典: https://fluttergemma.dev/docs/models （2026-09-18 時点）。
library;

/// モデルの種類。flutter_gemma の ModelType に1対1で対応する（依存を避けるため自前で持つ）。
enum LlmFamily { gemmaIt, gemma4, qwen3 }

class LlmModelSpec {
  const LlmModelSpec({
    required this.id,
    required this.label,
    required this.family,
    required this.url,
    required this.bytes,
    required this.note,
  });

  /// 端末に置くときのファイル名。同じ名前だと取り違えるので、モデルごとに変える。
  final String id;
  final String label;
  final LlmFamily family;
  final String url;
  final int bytes;

  /// 選ぶときの手がかり（速さ・日本語・容量）。
  final String note;

  String get sizeText {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    return bytes >= gb ? '${(bytes / gb).toStringAsFixed(1)} GB' : '${(bytes / mb).round()} MB';
  }
}

/// 軍師に使える候補。上から順に軽い。
const gunshiModels = <LlmModelSpec>[
  LlmModelSpec(
    id: 'gunshi-qwen3-0.6b.litertlm',
    label: 'Qwen3 0.6B',
    family: LlmFamily.qwen3,
    url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/model.litertlm',
    bytes: 614 * 1024 * 1024,
    note: 'いちばん軽い。動作確認向け。日本語はときどき崩れる',
  ),
  LlmModelSpec(
    id: 'gunshi-gemma3-1b.litertlm',
    label: 'Gemma 3 1B',
    family: LlmFamily.gemmaIt,
    url: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.litertlm',
    bytes: 537 * 1024 * 1024,
    note: '軽くて速い。まずはこれで口調が保てるかを見る',
  ),
  LlmModelSpec(
    id: 'gunshi-gemma4-e2b.litertlm',
    label: 'Gemma 4 E2B',
    family: LlmFamily.gemma4,
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/model.litertlm',
    bytes: 2458 * 1024 * 1024,
    note: '本命。日本語が安定するが大きい（Wi-Fi 推奨）',
  ),
];

/// 既定はいちばん軽い Gemma 3 1B。実機で E2B が通れば入れ替える。
const defaultGunshiModel = 1;
