# EcoWeather iOS — Master Specification (Merged)

**Project Name:** EcoWeather iOS (Unsigned/Sideload Edition)  
**Codename:** EcoLens  
**Version:** Merged canonical (from claude3, chatgpt2, gemini1, perplexity4)

---

## 0. Mission

Build a fully functional, real-data-driven eco-intelligence iOS app that helps users make smarter environmental and energy decisions in real time. This is not a demo, mockup, or prototype. Every system must be real, computed, connected, and production-minded.

The app should feel like:

> “A futuristic environmental assistant that helps users make smarter energy decisions in real time.”

---

## 1. Target Stack

| Layer | Technology |
|-------|------------|
| UI Layer | Swift / SwiftUI |
| Bridge Layer | Objective-C++ (`.mm` files) |
| Core Logic Engine | Plain C |
| Weather API | Open-Meteo (free, no key required) |
| Carbon API | Electricity Maps (with offline fallback) |
| CI/CD | GitHub Actions |

---

## 2. Guiding Principles

- **No placeholder logic anywhere.** Every function must be real, computed, and connected.
- **All features must be fully implementable** — no stubs, no TODOs, no fake returns.
- **Code must be clean, modular, and production-ready.**
- **Prioritize real-world usefulness over aesthetics** — but the UI must still feel premium (2026 “Liquid Glass” aesthetic: materials, depth, animated state transitions).
- **All network and compute-heavy work must be async** and non-blocking.
- **All outputs must be clamped and validated** to avoid NaN, overflow, or invalid state.

---

## 3. Core Engine — Plain C Only

All environmental calculations must be written in **pure C**. No Swift math shortcuts.

### 3.1 Thermal Delta Efficiency Engine

```c
float calculate_eco_ventilation_score(
    float outdoorTemp,
    float indoorTemp,
    float humidity
);
```

**Requirements:**

- Compute heat index using the **standard NOAA-style** Rothfusz regression (temperature + relative humidity), with temperatures converted via Celsius ↔ Fahrenheit as required by the formula.
- Compare indoor vs. outdoor thermal comfort.
- Apply a **humidity discomfort penalty** when relative humidity exceeds 60%.
- Apply **diminishing returns** for extreme outdoor temperatures (e.g., outdoor temp > 38°C or < 5°C).
- Factor in **temperature delta** between indoor and outdoor.
- Output a clamped score from `0.0` to `1.0`:
  - `0.0` → Keep windows closed; HVAC recommended.
  - `1.0` → Open windows immediately; optimal passive cooling.
- Must **never return NaN or overflow** — clamp all intermediate values.

### 3.2 Carbon Forecast Engine

```c
typedef struct {
    float co2_intensity;       // gCO2eq per kWh (fetched or estimated)
    int recommendation_level;  // 0 = Low, 1 = Medium, 2 = High
} GridStatus;
```

**Classification:**

| Level | Range | Meaning |
|-------|--------|---------|
| 0 (Low/Clean) | < 150 gCO2eq/kWh | “Good time to run appliances.” |
| 1 (Medium) | 150–400 gCO2eq/kWh | “Consider delaying non-essential usage.” |
| 2 (High/Dirty) | > 400 gCO2eq/kWh | “Delay energy use if possible.” |

**Fallback (offline / stale):**

- Use cached last-known `GridStatus` if available.
- If cache is older than 6 hours or missing, estimate using regional grid averages (hardcoded by ISO region code supplied by the app layer).
- Never block the UI thread; always return a valid `GridStatus`.

### 3.3 Smart Decision Fusion Engine

```c
typedef struct {
    float ventilation_score;
    GridStatus grid;
    int final_action;          // 0 = HVAC, 1 = Open Windows, 2 = Delay Energy Use
    char recommendation[128];  // Human-readable action string (NUL-terminated)
} EcoDecision;
```

**Fusion logic:**

- `ventilation_score > 0.7` **and** carbon is Low (level 0) → `final_action = 1` (Open Windows).
- `ventilation_score <= 0.7` **and** carbon is Low → `final_action = 0` (HVAC OK).
- Carbon is **High** (level 2), regardless of ventilation → `final_action = 2` (Delay Energy Use).
- **Medium** carbon (level 1): if `ventilation_score > 0.7` → `final_action = 1`; else → `final_action = 0`, with recommendation text reflecting medium carbon guidance.
- **Both bad** (poor ventilation + high carbon): minimal usage mode; recommend waiting (`final_action = 2` with explicit copy).
- Populate `recommendation` with a plain-English string based on `final_action` and grid level.

---

## 4. Bridge Layer — Objective-C++

- Wrap **all C functions and structs** in `.mm` files.
- Expose clean, Swift-consumable interfaces (`@objc` where appropriate).
- Convert C structs → Swift-friendly value types; **never** expose raw C pointers to Swift.
- **Zero memory leaks** — ARC-safe patterns; manually manage any C-allocated memory.

---

## 5. SwiftUI Frontend — Liquid Glass

### Visual language

- `UltraThinMaterial` as the base background on major surfaces.
- Blur depth layers for hierarchy (near / mid / far).
- Dynamic tint driven by `GridStatus` (not Gemini’s mistaken “Amber for high” — use the table below).

| Carbon Level | Color | Hex |
|--------------|--------|-----|
| Low (Clean) | Deep Emerald | `#00A86B` |
| Medium | Soft Amber | `#FFBF00` |
| High (Dirty) | Warm Red | `#FF4C4C` |

- State transitions use smooth animation (e.g. `.animation(.easeInOut(duration: 0.6), value: ...)`). No hard color cuts.

### Screens

1. **Dashboard** — Outdoor temperature (Open-Meteo, cached), central eco score orb, dynamic recommendation, carbon badge, offline/stale indicator.
2. **Decision Orb** — Glass sphere, pulse tied to `ventilation_score`, color from carbon state; tap expands detail.
3. **Detail Panel** — Indoor vs outdoor delta, humidity discomfort, carbon gCO2eq/kWh with trend vs last reading, `final_action` explanation, last-updated time.
4. **Hidden Debug Menu** — **Triple-tap** any corner of Dashboard: `build_metadata.json`, build timestamp (ISO 8601), carbon commit (`LOW | MEDIUM | HIGH | UNKNOWN`), raw API values; debug UI tint from **build-time** `carbon_commit`, not runtime.

---

## 6. Data Layer

### Weather — Open-Meteo

- Endpoint: `https://api.open-meteo.com/v1/forecast`
- Parameters: `latitude`, `longitude`, `current_weather=true`, `hourly=relativehumidity_2m`
- Cache last successful response to disk; on failure use cache and show stale badge.
- Network: `async/await` in Swift; never block the main thread.
- Throttle refreshes (e.g. max once per 15 minutes in background) to save battery.

### Carbon — Electricity Maps

- Endpoint: `https://api.electricitymap.org/v3/carbon-intensity/latest` (or current API path supported by the token).
- Header: `auth-token` — user supplies key in app settings (not committed to git).
- Fallback chain: cache → if stale (>6h) regional estimate → log reason for debug.

---

## 7. Build-Time Intelligence

GitHub Actions generates `build_metadata.json` and injects it at `Resources/build_metadata.json`.

```json
{
  "build_time": "2026-04-17T14:32:00Z",
  "run_number": 42,
  "carbon_commit": "LOW"
}
```

- CI may query Electricity Maps at build time and map to `LOW | MEDIUM | HIGH` using the same thresholds as the C engine.
- If unavailable: `"UNKNOWN"`.
- App reads at launch; display only in debug panel; debug tint uses **build-time** value.

---

## 8. GitHub Actions — “Monster Pipeline”

**Triggers:** push to `main` or `release/**`, `workflow_dispatch`.

**Outline:** checkout → Xcode → optional carbon fetch → write `build_metadata.json` → inject into bundle resources → `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO` → `CURRENT_PROJECT_VERSION` = `${{ github.run_number }}` → package `Payload/EcoWeather.app` → zip `.ipa` → upload artifact → log carbon summary.

---

## 9. Performance and Edge Cases

| Concern | Requirement |
|---------|----------------|
| API calls | Fully async; never block main thread |
| Offline | Ventilation score still computes locally; cached weather/carbon |
| NaN / overflow | Clamp C outputs; validate before bridging |
| Battery | Throttle weather refresh (e.g. 15 min) |
| Memory | No leaks across ObjC++ bridge |
| Errors | Non-blocking banners, not modal alerts |

---

## 10. Future Extensions (design for, do not block v1)

- WidgetKit, Apple Watch, push notifications (“best time to open windows”), Core ML comfort model, Siri Shortcuts.

---

## 11. Recommended Repository Layout

```
EcoWeather/
├── Core/
├── Bridge/
├── EcoWeather/           # App target sources
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   └── Resources/
├── docs/
│   └── MASTER_SPEC.md
├── .github/workflows/
└── EcoWeather.xcodeproj
```

---

## 12. Implementation Checklist

- [ ] All C functions fully implemented (no stubs)
- [ ] Heat index uses NOAA-style Rothfusz logic
- [ ] Carbon thresholds 150 / 400
- [ ] Fusion logic covers Low / Medium / High and `recommendation[128]`
- [ ] ObjC++ bridge leak-free
- [ ] SwiftUI `UltraThinMaterial`, animated tints
- [ ] Open-Meteo async + cache
- [ ] Electricity Maps + fallback chain
- [ ] `build_metadata.json` generated/injected in CI
- [ ] Unsigned `.ipa` artifact on macOS runners
- [ ] Build number from `github.run_number`
- [ ] Debug menu: triple-tap
- [ ] No blocking on main thread

---

*Merged from: ecoidea_claude3.md, ecoidea_chatgpt2.md, ecoidea_gemini1.md, ecoidea_perplexity4.md — 2026-04-17. Perplexity v2.0’s single `char recommendation` was rejected in favor of `char recommendation[128]`.*
