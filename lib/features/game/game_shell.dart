import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/llm/gemma_client.dart';
import '../../core/mind/mind_state.dart';
import '../../core/shogi/shogi.dart';
import '../about/about_page.dart';
import '../llm/model_page.dart';
import '../settings/app_settings.dart';
import '../settings/settings_page.dart';
import 'board_view.dart';
import 'design_hud.dart';
import 'game_controller.dart';
import 'game_setup_page.dart';
import 'memory_sheet.dart';
import 'review_page.dart';

enum _Panel { emotion, chat, log, menu, move, offer, result }

class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});
  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  _Panel? _panel;
  bool _targets = false, _resultDismissed = false;
  void _open(_Panel? panel) {
    FocusScope.of(context).unfocus();
    setState(() {
      _panel = panel;
      _targets = false;
    });
  }

  Future<void> _push(Widget page) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _copyKif() async {
    await Clipboard.setData(
      ClipboardData(
        text: toKif(
          ref.read(gameControllerProvider).game,
          startedAt: DateTime.now(),
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('KIFをコピーしました')));
    }
  }

  Future<void> _playCandidates(List<Move> candidates) async {
    if (candidates.isEmpty) return;
    final ctl = ref.read(gameControllerProvider.notifier);
    final position = ref.read(gameControllerProvider).position;
    Move? move;
    if (candidates.length == 1) {
      move = candidates.first;
    } else {
      final promote = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('成りますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('不成'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('成る'),
            ),
          ],
        ),
      );
      if (promote == null || !mounted) return;
      move = candidates.firstWhere((m) => m.promote == promote);
    }
    // Time can expire while the promotion chooser is open.
    final now = ref.read(gameControllerProvider);
    if (now.game.isOver ||
        now.pendingOffer != null ||
        now.thinking ||
        !identical(position, now.position)) {
      return;
    }
    ctl.play(move);
    if (mounted) _open(null);
  }

  Future<void> _resign() async {
    if (ref.read(settingsProvider).confirmResign) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('投了しますか？'),
          content: const Text('この対局を終了します。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('投了'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final s = ref.read(gameControllerProvider);
    if (s.game.isOver || s.thinking || s.mode.isAi(s.position.turn)) return;
    ref.read(gameControllerProvider.notifier).resign();
    _open(null);
  }

  void _settings() {
    final s = ref.read(gameControllerProvider);
    _push(
      SettingsPage(
        gameInProgress:
            !s.game.isOver &&
            (s.game.moves.isNotEmpty || s.mode != OpponentMode.human),
        onPreparation: () => _push(const GameSetupPage()),
        onModels: () => _push(ModelPage(store: GunshiModelStore())),
        onMemory: () => MemorySheet.show(context),
        onAbout: () => _push(const AboutAppPage()),
        onReview: () => _push(const ReviewPage()),
        onCopyKif: _copyKif,
      ),
    );
  }

  Widget _status(GameViewState s) {
    final result = s.game.result;
    final String status =
        result?.label ??
        (s.pendingOffer != null
            ? '軍師の提案に答えてください'
            : s.thinking
            ? '軍師が一手を思考中…'
            : '${s.game.moves.length + 1}手目 ${s.position.turn.mark}${s.position.turn.label}の番${s.position.inCheck(s.position.turn) ? '（王手）' : ''}');
    final clock = s.clock;
    final clockText = clock == null || clock.control.unlimited
        ? '時間無制限'
        : '▲ ${clock.of(Side.black).text}　△ ${clock.of(Side.white).text}';
    return Semantics(
      liveRegion: s.pendingOffer != null,
      child: SizedBox(
        height: 48,
        child: InkWell(
          onTap: s.pendingOffer != null ? () => _open(_Panel.offer) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                status,
                key: const ValueKey('status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(
                s.pendingOffer != null
                    ? '返答待ち・$clockText'
                    : s.observing
                    ? '局面を確認中・$clockText'
                    : clockText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(GameViewState s) {
    final ctl = ref.read(gameControllerProvider.notifier);
    final myTurn = !s.thinking && !s.mode.isAi(s.position.turn);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.touch_app_outlined),
          title: const Text('大きな着手操作'),
          subtitle: const Text('48dpの一覧から駒と移動先を選ぶ'),
          onTap: myTurn && !s.game.isOver ? () => _open(_Panel.move) : null,
        ),
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('待った'),
          onTap: !s.thinking && (s.game.moves.isNotEmpty || s.game.isOver)
              ? () {
                  ctl.undo();
                  _open(null);
                }
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('投了'),
          onTap: myTurn && !s.game.isOver ? _resign : null,
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('新規対局'),
          onTap: s.thinking ? null : () => _push(const GameSetupPage()),
        ),
        if (s.declaration?.canDeclare == true && myTurn && !s.game.isOver)
          ListTile(
            title: const Text('入玉宣言'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('入玉を宣言しますか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('戻る'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('宣言'),
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) {
                ctl.declareWin();
                _open(null);
              }
            },
          ),
        ListTile(
          leading: const Icon(Icons.history_edu),
          title: const Text('感想戦'),
          onTap: () => _push(const ReviewPage()),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all),
          title: const Text('KIFをコピー'),
          onTap: _copyKif,
        ),
        if (s.game.isOver)
          ListTile(
            title: const Text('結果を見る'),
            onTap: () => setState(() => _resultDismissed = false),
          ),
      ],
    );
  }

  String _square(int sq) => '${fileOf(sq)}${'一二三四五六七八九'[rankOf(sq) - 1]}';
  Widget _moves(GameViewState s) {
    final ctl = ref.read(gameControllerProvider.notifier);
    if (s.thinking || s.game.isOver || s.mode.isAi(s.position.turn)) {
      return const Center(child: Text('今は着手できません'));
    }
    if (_targets) {
      final targets = s.legalTargets.toList()..sort();
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: const Text('駒を選び直す'),
            onTap: () => setState(() => _targets = false),
          ),
          if (targets.isEmpty) const ListTile(title: Text('この駒の移動先はありません')),
          for (final sq in targets)
            ListTile(
              key: ValueKey('large-target-$sq'),
              title: Text('${_square(sq)}へ'),
              onTap: () => _playCandidates(ctl.tapSquare(sq)),
            ),
        ],
      );
    }
    return ListView(
      children: [
        const ListTile(title: Text('動かす駒を選んでください')),
        for (var sq = 0; sq < 81; sq++)
          if (s.position.board[sq]?.side == s.position.turn)
            ListTile(
              key: ValueKey('large-piece-$sq'),
              title: Text(
                '${_square(sq)}の${s.position.board[sq]!.type.kifName}',
              ),
              onTap: () {
                if (s.selection is! SquareSelection ||
                    (s.selection as SquareSelection).square != sq) {
                  ctl.tapSquare(sq);
                }
                setState(() => _targets = true);
              },
            ),
        for (final type in handOrder)
          if (s.position.handCount(s.position.turn, type) > 0)
            ListTile(
              title: Text(
                '持ち駒の${type.kifName} ${s.position.handCount(s.position.turn, type)}枚',
              ),
              onTap: () {
                if (s.selection is! HandSelection ||
                    (s.selection as HandSelection).type != type) {
                  ctl.tapHand(s.position.turn, type);
                }
                setState(() => _targets = true);
              },
            ),
      ],
    );
  }

  Widget _result(GameViewState s) {
    final r = s.game.result!;
    final side = s.mode.gunshiSide;
    final win = side != null && r.winner == side.opponent;
    final title = r.winner == null
        ? '引き分け'
        : side == null
        ? '${r.winner!.label}の勝ち'
        : win
        ? '君の勝ち'
        : '軍師の勝ち';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (side != null)
                    GunshiFace(
                      mood: r.winner == null
                          ? Mood.coverUp
                          : win
                          ? Mood.meltdown
                          : Mood.smug,
                    ),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  Text(r.label),
                  if (side != null && s.speech != null)
                    Text(
                      s.speech!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => _push(const ReviewPage()),
              child: const Text('感想戦へ'),
            ),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => _push(const GameSetupPage(repeat: true)),
              child: const Text('同じ設定で再戦'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gameControllerProvider);
    ref.listen(gameControllerProvider.select((s) => s.game.result), (
      prev,
      next,
    ) {
      if (next != prev) setState(() => _resultDismissed = false);
    });
    ref.listen(gameControllerProvider.select((s) => s.pendingOffer), (
      prev,
      next,
    ) {
      if (next != null) {
        FocusScope.of(context).unfocus();
        setState(() => _panel = null);
      } else if (_panel == _Panel.offer) {
        setState(() => _panel = null);
      }
    });
    final active = s.game.isOver && !_resultDismissed
        ? _Panel.result
        : s.pendingOffer != null
        ? _Panel.offer
        : _panel;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final mind = s.mind != null;
    final expandedText = MediaQuery.textScalerOf(context).scale(12) > 12;
    return PopScope(
      canPop: active == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || active == _Panel.offer) return;
        if (active == _Panel.result) {
          setState(() => _resultDismissed = true);
        } else {
          _open(null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 48,
          title: const Text('煽り将棋'),
          actions: [
            IconButton(
              tooltip: '設定',
              onPressed: _settings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = c.maxHeight, w = c.maxWidth;
                    if (h < 200) {
                      return Column(
                        children: [
                          const Text('画面を広げて対局してください'),
                          Expanded(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: IgnorePointer(
                                  child: BoardView(onCandidates: (_) {}),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    if (active != null) {
                      final p = keyboard && active == _Panel.chat
                          ? 104.0
                          : math.min(320.0, h - 152);
                      final b = math.max(48.0, math.min(w, h - p - 56));
                      final title = switch (active) {
                        _Panel.emotion => '軍師の感情',
                        _Panel.chat => '軍師に話しかける',
                        _Panel.log => '会話の記録',
                        _Panel.menu => '対局メニュー',
                        _Panel.move => '大きな着手操作',
                        _Panel.offer => '軍師からの提案',
                        _Panel.result => '対局終了',
                      };
                      return Column(
                        children: [
                          _status(s),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: b,
                                height: b,
                                child: IgnorePointer(
                                  child: BoardView(onCandidates: (_) {}),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: p,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 48,
                                    child: Row(
                                      children: [
                                        if (active != _Panel.offer)
                                          IconButton(
                                            tooltip: '盤へ戻る',
                                            onPressed: () {
                                              if (active == _Panel.result) {
                                                setState(
                                                  () => _resultDismissed = true,
                                                );
                                              } else {
                                                _open(null);
                                              }
                                            },
                                            icon: const Icon(Icons.expand_more),
                                          )
                                        else
                                          const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (active == _Panel.chat)
                                          IconButton(
                                            tooltip: '会話の記録',
                                            onPressed: () => _open(_Panel.log),
                                            icon: const Icon(Icons.history),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, panelSize) {
                                        final content = switch (active) {
                                          _Panel.emotion =>
                                            const EmotionDetails(),
                                          _Panel.chat => ChatPanel(
                                            key: const ValueKey(
                                              'conversation-composer',
                                            ),
                                            keyboardVisible: keyboard,
                                          ),
                                          _Panel.log => const ChatPanel(
                                            logOnly: true,
                                          ),
                                          _Panel.menu => _menu(s),
                                          _Panel.move => _moves(s),
                                          _Panel.offer => const OfferRow(
                                            keyName: 'offer-head',
                                          ),
                                          _Panel.result => _result(s),
                                        };
                                        if ((active == _Panel.offer ||
                                                active == _Panel.result) &&
                                            panelSize.maxHeight < 160) {
                                          return SingleChildScrollView(
                                            child: SizedBox(
                                              height: 200,
                                              child: content,
                                            ),
                                          );
                                        }
                                        return content;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    final deal = mind && s.dealTurns > 0 ? 48.0 : 0.0;
                    final compact = h < w + 360 + deal;
                    final hud = mind
                        ? (compact ? (expandedText ? 80.0 : 72.0) : 152.0) +
                              deal
                        : 0.0;
                    final minHeight = 208 + hud;
                    final tiny = h < minHeight + 96;
                    final b = math.max(
                      48.0,
                      math.min(w, h - (tiny ? 104 : minHeight)),
                    );
                    return Column(
                      children: [
                        if (mind && !tiny)
                          GunshiPanel(
                            compact: compact,
                            onSpeech: () => _open(_Panel.log),
                          ),
                        const Spacer(),
                        _status(s),
                        if (!tiny)
                          SizedBox(
                            height: 48,
                            child: KomadaiView(
                              side: Side.white,
                              label: s.mode.isAi(Side.white) ? '軍師' : null,
                            ),
                          ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: b,
                          height: b,
                          child: BoardView(onCandidates: _playCandidates),
                        ),
                        const SizedBox(height: 4),
                        if (!tiny)
                          SizedBox(
                            height: 48,
                            child: KomadaiView(
                              side: Side.black,
                              label: s.mode.isAi(Side.black) ? '軍師' : null,
                            ),
                          ),
                        if (!tiny) const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              if (mind)
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => _open(_Panel.emotion),
                                    child: const Text('感情'),
                                  ),
                                ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      _open(mind ? _Panel.chat : _Panel.move),
                                  child: Text(mind ? '煽る' : '着手操作'),
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () => _open(_Panel.menu),
                                  child: const Text('対局メニュー'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
