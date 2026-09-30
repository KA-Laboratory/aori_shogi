> 2026-09-29追記: 外見と現行画像は [確定マスコット仕様](MASCOT-20260929.md) に更新。以下は旧デザインの履歴です。

# 軍師画像・生成来歴

作成日: 2026-09-20。制作手段: Codex built-in image_gen。ユーザー依頼に基づくAI生成イラスト。既存作品・実在人物・第三者素材は参照入力に使用していない。制作仕様は `01-character.md` と `02-expressions.md`。

## 実際の納品

5つのMoodと対応する透過PNGを `assets/gunshi/` に保存した。全て1254×1254px、32bit ARGB。System.Drawingで実ファイルを開いて寸法・ピクセル形式・左上ピクセルのalpha=0を確認した。表示画像でも背景の市松模様が描かれた失敗版と区別した。PNGをコピーしただけで原画への画像加工は行っていない。全5枚合計5,289,885 bytes。ファイルサイズとSHA256は `assets/gunshi/manifest.csv`。

| Mood | ワークスペース納品 | 保存された生成原画 |
|---|---|---|
| composed | assets/gunshi/face_composed.png | C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-e173401b-6c64-4c62-a2e8-29823ac71a4f.png |
| smug | assets/gunshi/face_smug.png | C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-32b5fbbb-b8e0-42c5-a3fa-921f0ed5a32c.png |
| rattled | assets/gunshi/face_rattled.png | C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-1d1c439c-a166-4f51-bce6-03fbdb1724c1.png |
| meltdown | assets/gunshi/face_meltdown.png | C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-b635f8d3-f2c8-4011-af66-cf457353701f.png |
| coverUp | assets/gunshi/face_coverUp.png | C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-0af3e7c5-3c53-4021-8101-efc965c2eeae.png |

## 検収上の制約

- 本納品は利用可能な生成原画PNG5枚であり、発注仕様の完全達成を意味しない。72/144/216pxロスレスWebP15枚、864pxレイヤー付きPSD、680KiB以下のランタイム総容量は未達。編集可能なPSDは生成されていない。
- 原画は顔・衣装に滑らかな陰影を含み、平面色＋影1段という厳密な制限には一致しない。全身4頭身を検査できる全身画は作っていない。
- 表情差分は基準画を参照して個別編集した。同一人物としての一貫性は目視確認したが、輪郭・目中心の0px一致は保証しない。生成ごとの微小な線・顎位置の変化がある。
- 二股前髪、縦溝付き菱形襟留め、3本線の軍配は5枚に存在する。前髪が原画の上端に近いため72dp円内表示では適切な内側余白が必要。厳密なセーフエリア検収・白縁0検収・発注者による表情識別受け入れは未完了。
- CC0-1.0付与や第三者による著作権譲渡を受けたとは主張しない。AI生成履歴を記録したもので、発注仕様の権利表を代替するものではない。

## 生成方法と保持

基準画composedを新規生成し、それを参照画像にして各Moodを1枚ずつ編集した。built-in以外のAPI/CLI生成、Python画像編集、背景マスクの手作業合成は使用していない。元の生成ファイルは上記生成ディレクトリに残し、選択結果だけをプロジェクトへコピーした。

最初のsmug/rattled/meltdownと背景除去の試行ではRGB画像に市松模様が描かれたため採用しなかった。基準画から短い編集指示で再生成した結果、実際のalphaを持つ5枚が揃った。非採用試行は生成ディレクトリに保持し、アプリには含めていない。

## 採用プロンプト（原文）

### composed

新規生成。

```text
Use case: stylized-concept. Asset type: original mobile shogi game HUD strategist portrait, composed expression master. Create one square 1024x1024 RGBA PNG with genuinely transparent background (alpha zero, no checkerboard drawn). Original adult Japanese fantasy strategist man, age 32, slim, mature face with long rounded contour and short chin, no facial hair. Bold dark outline #24211E, flat opaque cel colors and just one shadow tone, simple highly readable shapes at 72px. Dark navy #263544 right-parted hair with a very distinctive two-pronged forelock at the top; thick straight eyebrows. Half-open eyes, brown #654A35 irises and ivory #FFF9EF whites, level brows, closed subtle one-sided confident smile, no sweat. Warm skin #E8B88F shadow #C99070. Navy short jinbaori vest with ivory #FFF1D5 collar, brass #CDA452 edging and centered brass DIAMOND collar clasp with ONE black vertical groove. Hold a small ivory military command paddle (gunbai) at lower viewer-right, face has EXACTLY THREE simple horizontal black lines, brown handle, visible gripping hand. Bust composition, turns 10 degrees toward viewer-right but eyes toward player. Keep generous transparent margin; hair, face, diamond and paddle fully contained within central circle of radius 42% of image. Eye midpoint about x50% y40%, chin y66%, diamond x46% y76%, paddle center x72% y65%. Broad face occupying most composition, 4-head stylization without childlike appearance. No background, border, halo, lettering, emblem, brand, existing-character resemblance, gradients, texture, realistic rendering, armor, weapons pointed at viewer. Identity silhouette and paddle will stay fixed across expression variants.
```

### smug

参照画像: C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-e173401b-6c64-4c62-a2e8-29823ac71a4f.png。

```text
Edit this PNG to make the man laugh proudly: closed joyful eyes, raised brows, open laughing mouth, rosy cheeks. Keep all other pixels, proportions, hair, coat, diamond clasp, fan and hand unchanged. Transparent background.
```

### rattled

参照画像: C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-e173401b-6c64-4c62-a2e8-29823ac71a4f.png。

```text
Edit this PNG to make the man rattled and anxious: wide-open eyes, inner eyebrows raised, small crooked worried mouth and one blue sweat drop on the viewer-left temple. Keep all other pixels, proportions, hair, coat, diamond clasp, fan and hand unchanged. Transparent background.
```

### meltdown

参照画像: C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-e173401b-6c64-4c62-a2e8-29823ac71a4f.png。

```text
Edit this PNG to make the man comically panic in a meltdown: big white eyes with tiny brown irises, uneven anxious eyebrows, tall wide-open shouting mouth, one thin blue tear stream on each cheek, eyes remain visible. Keep all other pixels, proportions, hair, coat, diamond clasp, fan and hand unchanged. Transparent background.
```

### coverUp

参照画像: C:/Users/amake/.codex/generated_images/01a0ba8a-f2b4-7fd1-acb1-252f6ccd29eb/exec-e173401b-6c64-4c62-a2e8-29823ac71a4f.png。

```text
Use case: identity-preserve. Input portrait is edit target. Keep same strategist character, pose, exact silhouette, face contour, nose, chin, hair with two-pronged forelock, navy coat ivory collar, brass diamond with black vertical groove, hand and paddle with three bars. Change ONLY facial expression to COVERING UP embarrassment: eyes look toward viewer-left, one eyebrow raised and other flat, a tight crooked CLOSED smile, one blue sweat drop at temple. Adult man attempts false composure. Retain positions, size and framing of all features except expression. Output isolated transparent-background character PNG cutout, actual transparent alpha; no checkered pattern or backdrop pixels. No text, no props.
```

## 非採用プロンプト（原文）

### smugPrompt

```text
Use case: identity-preserve. Edit the attached composed strategist portrait into the smug expression for the SAME game character. CHANGE ONLY eyes, eyebrows, mouth and cheek blush: eyes become thin joyous closed upward arcs, brows raised, mouth open in proud hearty laughter, soft rose cheek blush. Preserve the exact head silhouette, two-pronged forelock, face contour, head angle, nose position, chin, navy and ivory clothing, gold diamond clasp with black vertical groove, hand and command paddle with three bars. Preserve original canvas size, every object location, scale and transparent alpha background. The mouth must read at 72px. No text, no background, no extra props. One square PNG, not a sheet.
```

### rattledPrompt

```text
Use case: identity-preserve. Edit target: attached original transparent composed strategist PNG. Change ONLY facial expression to RATTLED: widened eyes and clear brown irises, inner eyebrows raised in anxious surprise, small crooked worried mouth, ONE blue sweat droplet at viewer-left temple. All hair, two-pronged forelock, face silhouette, nose, chin, clothing, gold diamond clasp and paddle with three bars, hand and all locations stay exactly unchanged. Output a genuinely transparent PNG with alpha=0 outside the character. CRITICAL: do NOT paint a grey checkerboard, grid, white or black backdrop; actual transparent alpha required. Keep original square dimensions and framing. No text. Same coherent adult character.
```

### meltdownPrompt

```text
Use case: identity-preserve. Attached portrait is the edit target. Make SAME adult strategist's MELTDOWN facial expression. Change only eyes/brows/mouth/tears: big white eyes with tiny brown irises, mismatched anxious eyebrows, mouth tall open in comic panicked shout, ONE thin tear stream per cheek, eyes remain fully visible. Preserve exact character silhouette and pose, hair, two-point forelock, navy ivory gold costume, diamond collar clasp with vertical black slit, hand and paddle with three horizontal black bars. Preserve their size and position. Produce an isolated character transparent-background PNG cutout. Absolutely NO checkerboard pattern in image pixels. True transparent alpha background, not an illustration of transparency. No text.
```

### smugAlphaPrompt

```text
Use case: background-extraction. Remove the entire gray and white checkerboard background from this image and return the character cutout on a REAL transparent PNG background with alpha channel. Preserve the illustrated laughing strategist exactly. Do not redraw or change his expression, costume or paddle. The checkerboard is unwanted image content, delete it all. No replacement background. Return RGBA PNG with transparency.
```

