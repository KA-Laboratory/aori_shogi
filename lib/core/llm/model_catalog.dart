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
    this.sha256,
  });

  /// 端末に置くときのファイル名。同じ名前だと取り違えるので、モデルごとに変える。
  final String id;
  final String label;
  final LlmFamily family;
  final String url;

  /// 正確なバイト数。ダウンロードの照合に使うので、概算を書かないこと。
  /// 0 なら「分からない」の意味で、照合を飛ばす。
  final int bytes;

  /// 配布元のハッシュ。自前で配るものには必ず入れる。
  /// 他所のモデルは公表されていないので null（サイズだけ見る）。
  final String? sha256;

  /// 選ぶときの手がかり（速さ・日本語・容量）。
  final String note;

  String get sizeText {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    return bytes >= gb ? '${(bytes / gb).toStringAsFixed(1)} GB' : '${(bytes / mb).round()} MB';
  }
}

/// 軍師の本命。Qwen3-1.7B（Apache 2.0）に自前の LoRA を統合して int8 にしたもの。
/// これだけが軍師の口調と場面の言い回しを学習している。他はどれも素のモデル。
///
/// ⚠ `url` はまだ決まっていない（`docs/dev/model_distribution.md`）。
/// Cloudflare R2 に上げて URL が決まったらここを差し替える。それまでは
/// 「端末に置いたファイルから入れる」（開発用）で adb push したものを使う。
const gunshiFinetuned = LlmModelSpec(
  id: 'gunshi-qwen3-1_7b-17g.litertlm',
  label: '軍師（学習済み）',
  family: LlmFamily.qwen3,
  url: '', // R2 の URL が決まったら入れる
  bytes: 1900934064,
  sha256: 'f89c7f1e3cf5504ae6237c39210fe58b9dfd5bb7c69a995279ba4b310b41a2c2',
  note: '軍師の口調を学習させたもの。これが本命（Wi-Fi 推奨）',
);

/// 素のモデル。軍師の口調は学習していないので、プロンプトだけで喋らせることになる。
/// サイズは配布元が公表していないので概算。ハッシュも無いので照合しない。
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
