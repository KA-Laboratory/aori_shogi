# Original procedural sound effects

Created: 2026-09-20. Generation: OpenAI Codex, for the aori_shogi project.
Source: `tools/generate_feedback_audio.py` in this repository. Deterministic additive synthesis of sinusoidal partials with short amplitude envelopes; no recordings, downloaded sounds, or third-party samples are incorporated.

These generated audio assets are delivered under **CC0-1.0** (public-domain dedication, to the extent any copyright or related rights exist). This describes the project's original generated assets; it does not assert that an external author licensed a sample or that AI-generated audio necessarily has copyright protection. Project contributors dedicate any rights they hold in these files under CC0-1.0.

License text: <https://creativecommons.org/publicdomain/zero/1.0/legalcode>

| File | Generator / source | Rights / dedication |
|---|---|---|
| piece_pick.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| piece_place.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| piece_promote.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| notice.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| taunt_hit.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| taunt_miss.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| result_win.wav | Codex procedural synthesis | Project original, CC0-1.0 |
| result_loss.wav | Codex procedural synthesis | Project original, CC0-1.0 |

Format: PCM WAV, 48 kHz, signed 16-bit mono; 44-byte headers. Eight files total 185,632 bytes. Check with `python tools/generate_feedback_audio.py --check`.

Acceptance: waveform format, lengths, peak, DC offset and file sizes are mechanically checked. Speaker/headphone listening on physical Android and iOS devices remains unverified. No BGM or voice is included.
