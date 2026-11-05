# Dear Home AI

Dear Home AI（亲爱的房子 AI）is the house in the Dear line: a local companion with a soul, an Apple Home reading, and a family queue. Miles / 大向 owns the product. This repository is the MVP-1 scaffold. It follows Dear Earth's engineering shape — XcodeGen, Swift 6, a CLS memory rhythm, a 1% evolution clamp, and the shared on-device model channel — and it does not reuse Dear Earth names in the interface.

The five tabs match the handwritten notebook: **Home**, **Space**, **Memories**, **Evolution**, **Setting**.

## Open it on the Mac

Dear Earth lives beside this app, typically at `~/Future/DearEarth`. Put this repo next to it and generate the project there:

```bash
cd ~/Future/DearHome
brew install xcodegen
xcodegen generate
open DearHome.xcodeproj
```

Scheme **DearHome**, team **XN42ZWWAT9** (already set, the same team as Dear Earth). Bundle id `com.s2.dearhome`. Display name **Dear Home AI** (App Store / home screen; bundle stays `com.s2.dearhome`). Deployment target iOS 17, Swift 6, strict concurrency.

On the App ID, enable the capabilities this project already declares:

- HomeKit
- App Groups: `group.com.robotzero.shared.ai` and `group.com.s2.dearuniverse`
- Background Modes → Background processing

`Info.plist` also reserves `com.s2.dearhome.midnight-distillation`, HomeKit and local-network usage strings (en + zh-Hans), and the Bonjour type `_mqtt._tcp`. Nothing browses the LAN in this build, so that permission is not requested yet.

Run the **DearHome** scheme on an iPhone simulator. The sample living room and dining room are on by default, so Space has a day to read before Apple Home is connected.

### Tests

This scaffold was written where an iOS Simulator is not available, so the tests were not executed here. On the Mac:

```bash
xcodebuild test -scheme DearHome -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use whichever simulator runtime is installed. The tests cover the 1% evolution clamp, MQTT envelope encode/decode, the daily-midnight / realtime state machine, the family-fact rules, the 30-day ring, pending distillation, and the 22-app share decision.

## Local chat (llama, same stack as Dear Earth)

`Vendor/llama.xcframework` is a symlink to Dear Earth's framework and is linked + embedded in `project.yml`. On launch, `AppModel.prepareLocalModelIfNeeded()` loads the first GGUF from:

1. `group.com.robotzero.shared.ai/models/` (green channel with Dear Earth)
2. `group.com.s2.dearuniverse/models/` (legacy share)
3. `Application Support/DearHome/models/` (local drop folder)

Preferred names: `Qwen3.5-2B`, `Qwen3-1.7B`, `Qwen3.5-0.8B`, `Qwen3-0.6B`. Chat goes through `HouseLLM` (ChatML / Qwen) with a short house system prompt plus `na_home_soul_corpus.json` (NA butler/smart-home SOUL, ~5k English words) and today's ≤1% evolution lean. Stereotype closings such as 「墙知道了」/「墙记住了」/“The wall knows” are stripped in `HouseLLM.sanitize` and must not be listed as forbidden phrases in the system prompt. Offline `LocalDialogueEngine` is fallback only and no longer appends template closings.

**To talk with the on-device model on a phone:** install Dear Earth on the same team build, download a Qwen GGUF there once (it publishes into the shared App Group), then rebuild Dear Home AI and open chat. Or copy a `.gguf` into the app's `Application Support/DearHome/models/` via the Files / share path you use for Dear Earth.

## What talks when there is no model

If no GGUF is found, `HomeCompanionEngine` falls back to `LocalDialogueEngine`, which reads `home_soul.json` and the skill snippets under `Resources/Skills/`. Climate, lights, family rhythm, and privacy are the seed skills. A control sentence is answered as a **suggestion**. This version never writes a HomeKit characteristic.

Private talk (a confession, or a crisis sentence) is answered on the phone and is not placed on the family queue. A crisis reply points at local emergency help, 988 in the US and Canada, and 400-161-9995 in mainland China.

## How this reuses Dear Earth

| Dear Earth | Dear Home |
|---|---|
| `EvolutionVector12D` + `MidnightEvolutionEngine`, step ≤ 0.01 | `EvolutionVector` (12 house axes) + the same clamp. A counterpart (owner, partner, child, elder, guest) may bias the raw gradient. The clamp still wins. A day with no talk does not drift. |
| `MidnightDailyScheduler` 300+300, no fake summary | `LocalDailyDistillJob`. If the provider is `.unavailable`, the day is appended to `PendingDistillation` and nothing is invented. |
| `WeeklyMondayConsolidator`, weight = cumulative × 0.7 + weekly × 1.5 | `LocalWeeklyConsolidator`. It reads daily summaries only, never the raw transcript. |
| 30-day FIFO, 7-day hot window, export warning near day 28 | `ThirtyDayRing`. Age ≥ 30 is evicted. A day with 3 or fewer days left raises the export capsule. |
| `EcosystemModelCenter`, `group.com.robotzero.shared.ai` | Same group, plus a probe for `group.com.s2.dearuniverse`. Priority is this app, then the 22-app green channel, then external apps only if Setting allows it (default off). |
| `Sandbox` under Application Support | `HomeSandbox` under `Application Support/DearHome/`. |
| `llama.xcframework` + `LlamaRuntime` + ChatML | Same framework (symlink `Vendor/llama.xcframework`), `LlamaRuntime`, `ChatTemplate`, `ModelLocator`, LLM-first `HomeCompanionEngine`. |

Storage layout:

```
Application Support/DearHome/
  UserProfile/preferences.json
  HomeAgent/home_01/
    agent_meta.json
    DaytimeLogs/raw_YYYY-MM-DD.jsonl
    Memories_MD/DearHome_YYYY-MM-DD.md
    Evolution_History/delta_YYYY-MM-DD.json
  FamilyLayer/bus.json
  Hippocampus/memory.json
  messages.json
  models/*.gguf   # optional local weights if App Group is empty
```

There is one house (`home_01`), not 23 celestials. Family facts are the shared layer. Personality stays on the device.

Dear Earth stores the hippocampus in SQLite. MVP-1 stores it as JSON plus the jsonl day log. The job interfaces are the same shape: day key, daily distill, weekly consolidator, ring metadata, pending queue.

## HomeKit

`HomeKitBridging` is the seam. `MockHomeProvider` feeds the notebook day:

- 07:00 living room, 25°C, humidity 60%, fan speed 1 — Apple Home
- 07:05 pendant light on — Dad's app
- 07:15 wall switch turns that light off — the house agent
- 11:15 dining room light, daughter's voice

Turn **Sample rooms** off in Setting to construct `LiveHomeKitBridge`. It reads homes, rooms, accessories, and scenes after authorization. `performWrite` throws `HomeKitControlError.suggestOnly`. Scenes are listed and not run.

## Family MQTT

The owner's iPhone is the gateway host. A family iPhone is a terminal. `FamilyTransport.usesEmbeddedBroker` is `false`: there is no socket and no embedded broker.

`FamilyMessageEnvelope` encodes `familyId`, `msgId`, `ts`, `kind` (`fact` | `event` | `digest`), `room`, `source`, `payload`, `syncMode` (`dailyMidnight` | `realtime`), and `sensitivity`. A missing sensitivity decodes as `family`. `sealed` envelopes are refused by `FamilyBus`.

`SyncModeMachine`:

- **realtime** — ingest returns the envelope immediately.
- **dailyMidnight** — the envelope stays in `pending` until a tick whose local day is after the envelope's day (the 00:00 exchange, including when the app opens later).
- Switching to realtime flushes what was waiting. Switching back to daily does not send those envelopes again.

Setting has **Run the 00:00 exchange now**, which ticks the machine at the next local midnight so the queue can be seen without waiting.

`RuleBasedFamilyFactExtractor` pulls room, device, action, time, and source from Chinese or English. A question with no action and no measurement is not a fact. Confessions are dropped before a room word can leak them.

## Shared model

`EcosystemModelCenter.scan` looks in the App Group container `models/` for a `.gguf`, and in `registry.json` for a publisher keyword. Setting shows one of: still looking, container missing, weight found but llama not linked, green channel, or external refused.

This build does not download a model and does not vendor weights.

### Linking llama later

Dear Earth's README builds `Vendor/llama.xcframework` (llama.cpp, MIT) and does not commit it. When that framework exists, add the same dependency Dear Earth uses:

```yaml
dependencies:
  - framework: Vendor/llama.xcframework
    embed: true
    codeSign: true
```

Then replace `LlamaRuntime.complete` with the real runner. Until `status` is `.ready`, midnight distillation keeps the day in `PendingDistillation` with reason `runtime_not_linked` or `no_model`. Catch-up on next launch fills those days. It does not summarize them with a hand-written rule.

## MVP-2

- A real MQTT broker on the owner phone, and a way for family phones to join (QR or LAN browse of `_mqtt._tcp`).
- Family-fact extraction through the shared model as well as the rules.
- Evolution curves over stored midnight steps, and a read-only comparison of household personas.
- SQLite for the hippocampus if the JSON store gets tight. Dear Earth's `HippocampusStore` is the pattern.

## MVP-3

HomeKit writes and scenes, after a separate authorization step. Subscription. App Store metadata.

## Product rules that the code enforces

- Suggest, do not seize the switch.
- Household facts may leave. Confessions do not.
- One percent a day is the most any axis may move, and only when a distillation actually ran. The Evolution preview is not saved.
- No model means a pending day, not a fake 300 + 300.
