# Secure Edu — Project Blueprint

A Flutter + Firebase app that streams private lectures only to approved students, with no downloadable or shareable links and with screen capture blocked on Android.

Code in this repo:

| Path | What it is |
|---|---|
| `app/` | Flutter app (Android + iOS). Passes `flutter analyze` with no issues. |
| `functions/` | Cloud Functions (TypeScript): `getPlaybackToken` plus an admin CLI |
| `firestore.rules` | Security rules. Clients can't write anything that grants access. |
| `rules-tests/` | Emulator tests for the rules (7 passing) |
| `firebase.json` | Firebase project config (rules, indexes, functions, emulators) |

---

## 1. Recommended stack

| Layer | Choice | Why |
|---|---|---|
| App | **Flutter 3.x** | One codebase for Android and iOS. Native access for `FLAG_SECURE`. `video_player` uses ExoPlayer and AVPlayer with HLS and playback speed. |
| Auth | **Firebase Auth**: email/password with mandatory email verification, plus Google Sign-In | Free tier is generous. Google accounts arrive already verified. |
| Database | **Cloud Firestore** | Real-time subscription status, and rules enforced on the server |
| Backend | **Cloud Functions (2nd gen, Node 22)** | The only component that can mint a video URL |
| Anti-abuse | **Firebase App Check** (Play Integrity / App Attest) | Scripts, emulators and modified APKs can't call the backend |
| Video | **Cloudflare Stream with signed URLs** (recommended). Bunny Stream or VdoCipher if you need DRM. | See §2 |

### How the security fits together

```
 Student app                          Firebase                         Cloudflare Stream
 ───────────                          ────────                         ─────────────────
 login (email verified) ─────────────► Auth
 read subscriptions/{email} ─────────► Firestore (rules: own doc only)
 tap lecture ──callable + AppCheck──► getPlaybackToken
                                         ✔ App Check token valid
                                         ✔ email_verified
                                         ✔ subscription active, covers course
                                         ✔ device ID == bound device
                                         ✔ videoSources/{id} (server-only)
                                         └─ sign RS256 JWT (exp ≈ video length + 30 min)
 ◄───────────── https://customer-x.cloudflarestream.com/<JWT>/manifest/video.m3u8
 VideoPlayer(HLS) ───────────────────────────────────────────────────► validates JWT on
                                                                        every segment request
```

What protects what:

- **The URL is useless to share.** It carries a signed token for one video and expires shortly after the lecture ends. The raw video ID is never sent to the app: it lives in `videoSources`, which only the server can read.
- **The URL can't be generated outside the app.** The function needs an App Check token, which only your signed app on a genuine device can produce.
- **An account can't be shared.** The first device to play a video is bound to the account, and other devices get `DEVICE_MISMATCH` until you reset it.
- **Screen capture.** `FLAG_SECURE` on Android. On iOS the app detects recording and mirroring, then pauses and hides the video.
- **Leaks can be traced.** A moving watermark shows the student's email and a short ID, and every playback is logged to `playbackLogs`.
- **The player has no outbound UI.** There's no share or download button, no title link and no "Watch on…" button.

> **Honest limits.** No app-level scheme makes video impossible to copy. Someone can film the screen with a second phone, and the watermark only makes that traceable. Without DRM, a technically skilled user on a rooted phone could capture the HLS stream while their token is valid. If your content is valuable enough that people will try this, add DRM (§2.3). Everything else in this blueprint stays the same.

---

## 2. Video hosting analysis

### 2.1 Can YouTube (Private/Unlisted + IFrame/Player API) meet this bar? **No.**

| Requirement | YouTube reality |
|---|---|
| Only subscribers can watch | **Private** videos can't be played in an embedded player by your students. They only play for up to 50 hand-invited Google accounts, signed in on youtube.com. **Unlisted** videos have no access control at all: anyone with the 11-character ID can watch. |
| No copyable link | The video ID has to reach the device to be embedded, so it is in the app's network traffic and memory and can be recovered by decompiling. `youtube.com/watch?v=<id>` then works in any browser, where `FLAG_SECURE` doesn't apply. |
| No download | Free tools such as `yt-dlp` download any unlisted video given its ID. |
| Hide YouTube UI (title, "Watch on YouTube", share, more videos) | `showinfo` was removed in 2018 and `modestbranding` stopped working in 2023. With `controls=0` the logo and title still appear in some states, and "More videos" shows on pause. |
| Cover or alter the player to hide branding | This **breaks the YouTube API Services Developer Policies**: you must not obscure, modify or hide the player or its attribution. Your API access can be terminated. |
| No ads on your lectures | YouTube can show ads on any video, including ones from non-monetized channels. |

**Verdict:** YouTube works as a free *public* channel. It can't protect paid content, because the security of the whole system collapses to "keep an 11-character string secret". Move your lecture library to a provider with signed URLs.

### 2.2 Alternatives compared

Prices are approximate as of 2026. Check the provider's pricing page before committing.

| Provider | Access control | DRM | Approx. cost | Notes |
|---|---|---|---|---|
| **Cloudflare Stream** ✅ recommended | Signed JWT URLs (`requireSignedURLs`), country/IP rules, downloads off by default | No | ~$5 per 1,000 min stored/month + $1 per 1,000 min watched | Simplest API and predictable pricing. This repo implements it. |
| **Bunny Stream** 💰 cheapest at scale | Token authentication, referrer lock | MediaCage Basic (obfuscation) included. Widevine/FairPlay "Enterprise DRM" is a paid add-on. | Storage ~$0.01/GB, delivery ~$0.005–0.01/GB | Often 5–10× cheaper than Stream when you have many viewing hours |
| **VdoCipher** 🔒 strongest out of the box | Per-user OTP tokens | Widevine + FairPlay included, dynamic watermark | Higher. Plans are sized by bandwidth. | Built for paid edu content. Has a Flutter SDK. |
| **Mux** | Signed playback IDs | DRM (add-on) | Per-minute encode/store/stream | Excellent API, but usually costs more than Stream |
| **Vimeo (Private/Hide from Vimeo)** | Domain-level privacy. Signed HLS needs a higher plan. | No | Plan-based | Built for web embeds, and the iframe has the same branding problems as YouTube. Not recommended for apps. |

**Rough monthly cost example** (Cloudflare Stream): 100 h of lectures = 6,000 min stored ≈ **$30**. 200 students × 15 h watched = 180,000 min ≈ **$180**. If viewing hours dominate your bill, compare Bunny Stream.

### 2.3 Upgrading to DRM later

All provider logic is inside `getPlaybackToken`, so switching to VdoCipher or Bunny Enterprise DRM is contained:

1. Store the provider's video ID in `videoSources/{videoId}` (`provider: "vdocipher"`).
2. In the function, request the provider's per-viewer OTP/license token instead of signing a JWT. Pass the student's email as watermark text.
3. In the app, swap `VideoPlayer` for the provider's Flutter player widget. Keep `PlayerControls` if the SDK lets you hide its own UI.

With Widevine L1 and FairPlay, the OS itself blacks out the video in recordings, including on iOS.

---

## 3. Firestore schema

```
users/{uid}                                  ← student profile
  name:          string        (client-editable)
  email:         string        (must equal auth token email)
  phone:         string        (client-editable)
  createdAt:     timestamp
  updatedAt:     timestamp
  boundDeviceId: string        (SERVER-ONLY: set by getPlaybackToken)
  boundAt:       timestamp     (SERVER-ONLY)

subscriptions/{emailLowercase}               ← ADMIN-ONLY write
  email:      string
  status:     "active" | "expired" | "revoked"
  plan:       string?          e.g. "Annual 2026"
  courseIds:  string[]         ["physics-11", "chem-11"] or ["*"] for all courses
  startsAt:   timestamp
  expiresAt:  timestamp
  updatedAt:  timestamp

courses/{courseId}                           ← ADMIN-ONLY write
  title, description: string
  thumbnailUrl:       string?
  order:              number
  published:          bool

courses/{courseId}/chapters/{chapterId}
  title:  string
  order:  number

courses/{courseId}/videos/{videoId}          ← public metadata, NO url
  chapterId:   string
  title:       string
  order:       number
  durationSec: number

videoSources/{videoId}                       ← SERVER-ONLY (rules: deny all)
  courseId:  string
  provider:  "cloudflare"
  streamUid: string

playbackLogs/{autoId}                        ← SERVER-ONLY audit trail
  uid, email, courseId, videoId, deviceId, at
```

Design choices:

- **Subscriptions are keyed by email, not uid.** You can approve a student before they install the app. When they sign up with that email and verify it, access appears instantly through the real-time listener.
- **Videos are flat under the course** with a `chapterId` field. The chapter screen loads with 2 queries and doesn't need a composite index.
- **Metadata is split from the source.** Even a fully compromised client can't learn the Cloudflare UID.

---

## 4. Step-by-step implementation

### Step 1: Prerequisites

```bash
# Flutter SDK (stable), Android Studio + Android SDK, JDK 17, Node 22
npm i -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

### Step 2: Firebase project

1. Create a project at <https://console.firebase.google.com>. Upgrade it to **Blaze** (pay-as-you-go), which Cloud Functions and Secret Manager require. Small apps stay within the free quotas.
2. Go to **Authentication → Sign-in method** and enable **Email/Password** and **Google**.
3. Go to **Firestore Database → Create database** in production mode. Pick a region near your students, such as `asia-south1`.
4. Connect the app:
   ```bash
   cd app
   flutterfire configure --project=<project-id> --platforms=android,ios
   ```
   This overwrites `lib/firebase_options.dart` and adds the Google Services Gradle plugin.
5. Copy the **Web client ID** into `AppConfig.googleServerClientId` (`app/lib/config.dart`). You'll find it under Authentication → Google → Web SDK configuration.
6. Add SHA fingerprints under **Project settings → Your apps → Android**. Google Sign-In and Play Integrity both need them.
   ```bash
   cd app/android && ./gradlew signingReport           # debug SHA-1/SHA-256
   keytool -list -v -keystore ~/secure-edu-release.jks  # release (step 6.1)
   ```
   If you publish through Play, also add the **Play App Signing** SHA-256 from Play Console → Setup → App signing.
7. For iOS: add the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` as a URL scheme in `ios/Runner/Info.plist` (`CFBundleURLTypes`).

### Step 3: Security rules, Auth rules and App Check

Deploy the rules and index:

```bash
cp .firebaserc.example .firebaserc   # set your project id
firebase deploy --only firestore
```

Key ideas in [`firestore.rules`](../firestore.rules):

```js
// A student can read only the subscription that matches their VERIFIED email
match /subscriptions/{email} {
  allow get: if verified() && request.auth.token.email.lower() == email;
  allow list, write: if false;            // Admin SDK only
}
// Students edit name/phone only, so they can never touch boundDeviceId
allow update: if request.auth.uid == uid
  && request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['name', 'phone', 'updatedAt']) ...;
// Video sources are invisible to every client
match /videoSources/{id} { allow read, write: if false; }
```

Verify the rules locally (needs Java):

```bash
cd rules-tests && npm install && npm test
```

**App Check:**

1. Go to Console → **App Check** → register the Android app with **Play Integrity** and the iOS app with **App Attest**.
2. Debug builds use the debug provider (`main.dart`). Run once, copy the debug token from logcat, and add it under App Check → Manage debug tokens.
3. `getPlaybackToken` already sets `enforceAppCheck: true`.

> ⚠️ Play Integrity only passes for apps **installed from Google Play**. To hand out a sideloaded APK instead, publish to a Play **internal/closed testing** track (free, up to 100 testers per list), or remove `enforceAppCheck` and accept weaker protection.

**Auth hardening** (Console → Authentication → Settings):

- Turn on **email enumeration protection**.
- Add your production domain under **Authorized domains** only.
- Set password policy to a minimum of 8 characters.

### Step 4: Cloudflare Stream and the playback function

1. Sign up for Cloudflare and enable **Stream**. Note your **Account ID** and the **customer subdomain** (`customer-<CODE>.cloudflarestream.com`).
2. Upload your lectures: drag and drop in the dashboard, or use tus/API for large files. To move existing YouTube videos, download your originals from YouTube Studio first.
3. Make every video require signed URLs:
   ```bash
   curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/stream/$VIDEO_UID" \
     -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
     --data '{"uid":"'$VIDEO_UID'","requireSignedURLs":true}'
   ```
   **Do not** enable MP4 downloads on any video.
4. Create a signing key:
   ```bash
   curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/stream/keys" \
     -H "Authorization: Bearer $CF_API_TOKEN"
   # → { result: { id: "...", pem: "LS0tLS1CRUdJTi..." } }
   ```
5. Configure and deploy the function:
   ```bash
   cd functions
   npm install
   cp .env.example .env.<project-id>        # STREAM_KEY_ID, STREAM_CUSTOMER_CODE
   firebase functions:secrets:set STREAM_KEY_PEM   # paste the base64 pem
   firebase deploy --only functions
   ```

The core of [`functions/src/index.ts`](../functions/src/index.ts):

```ts
export const getPlaybackToken = onCall(
  { enforceAppCheck: true, secrets: [STREAM_KEY_PEM] },
  async (request) => {
    // 1. auth + email_verified   2. subscription covers course
    // 3. device binding (transaction)   4. read server-only videoSources
    const token = jwt.sign(
      { sub: streamUid, kid: keyId, nbf: now - 30, exp },
      pem, { algorithm: "RS256", keyid: keyId });
    return { url: `https://customer-${code}.cloudflarestream.com/${token}/manifest/video.m3u8`,
             expiresAt: exp * 1000, watermark: `${email} · ${uid.slice(0, 6)}` };
  });
```

### Step 5: Managing students and content (admin CLI)

```bash
cd functions
gcloud auth application-default login
export GOOGLE_CLOUD_PROJECT=<project-id>
export CF_ACCOUNT_ID=... CF_API_TOKEN=...     # optional: auto-fills durations

npm run admin -- add-course  physics-11 1 "Physics Class 11" "NCERT + JEE"
npm run admin -- add-chapter physics-11 ch01 1 "Units and Measurement"
npm run admin -- add-video   physics-11 ch01 ch01-l01 <streamUid> 1 "Introduction"

npm run admin -- grant  student@gmail.com physics-11 365 "Annual"
npm run admin -- grant  topper@gmail.com '*' 30 "Monthly – all courses"
npm run admin -- revoke student@gmail.com          # also signs them out
npm run admin -- reset-device student@gmail.com    # student changed phones
npm run admin -- list-subs
```

When you're ready, the next step is an admin web panel (Flutter Web or a small React app), backed by callable functions that check an `admin` custom claim.

### Step 6: Blocking screenshots and screen recording

**Android.** In [`MainActivity.kt`](../app/android/app/src/main/kotlin/com/yourinstitute/secure_edu/MainActivity.kt), `FLAG_SECURE` is applied app-wide before the first frame:

```kotlin
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
}
```

The effect: screenshots, screen recorders (including the built-in one), the Recents thumbnail and casting to non-secure displays all show **black**. Also, `android:allowBackup="false"` stops the session and device ID from being cloned through backups.

**iOS.** Apple provides **no API to block** screenshots or recording. The app does the strongest thing allowed:

- `ScreenSecurityPlugin` in [`AppDelegate.swift`](../app/ios/Runner/AppDelegate.swift) streams `UIScreen.isCaptured` to Dart.
- `PlayerScreen` **pauses and hides** the video while recording, AirPlay or mirroring is active.
- For true blocking on iOS, use FairPlay DRM (§2.3). iOS then blacks out the protected video in recordings.

**Dart side** ([`screen_security.dart`](../app/lib/security/screen_security.dart)):

```dart
_captureSub = ScreenSecurity.isCaptured.listen((captured) {
  if (captured) _controller?.pause();
  setState(() => _captured = captured);   // replaces video with a notice
});
```

Optional extra hardening: root and jailbreak detection with hook and tamper checks (for example the `freerasp` package). Rooted devices can strip `FLAG_SECURE` with Xposed-style modules.

### Step 7: Secure player with restricted controls

[`player_screen.dart`](../app/lib/screens/player_screen.dart) and [`player_controls.dart`](../app/lib/widgets/player_controls.dart):

- `VideoPlayerController.networkUrl(grant.url, formatHint: VideoFormat.hls)`. The URL is held only in memory and is never shown, logged or copyable.
- Custom overlay: play/pause, ±10 s, scrubber, time, **speed menu (0.75×, 1×, 1.25×, 1.5×, 2×)** through `controller.setPlaybackSpeed`, and fullscreen (landscape + immersive).
- No YouTube or platform chrome at all. There's no title link, share, "Watch on…", related videos or download.
- `MovingWatermark` with the student's email moves every 15 s.
- The video pauses when the app goes to the background (`didChangeAppLifecycleState`), the screen stays awake while watching (`wakelock_plus`), and background playback is disabled.

```dart
PopupMenuButton<double>(
  itemBuilder: (_) => [
    for (final s in AppConfig.playbackSpeeds)       // [0.75, 1, 1.25, 1.5, 2]
      PopupMenuItem(value: s, child: Text(_label(s))),
  ],
  onSelected: (s) => controller.setPlaybackSpeed(s),
  ...
)
```

### Step 8: App flow

```
AuthGate (userChanges stream)
 ├─ signed out ───────────────► LoginScreen  (email/password, Google, forgot pwd)
 │                                └─ RegisterScreen (name, email, phone, password → verification mail)
 ├─ email not verified ───────► VerifyEmailScreen (resend / "I've verified" → reload + token refresh)
 ├─ no active subscription ───► NoAccessScreen   (live: unlocks the moment you run `grant`)
 └─ active ───────────────────► CoursesScreen ─► CourseDetailScreen (chapters ▸ lectures) ─► PlayerScreen
                                   └─ ProfileScreen (edit name/phone, plan & expiry, sign out)
```

---

## 5. Building the Android APK / App Bundle

### 5.1 Create a release signing key (one time, and keep it safe forever)

```bash
keytool -genkey -v -keystore ~/secure-edu-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias secure-edu
```

Create `app/android/key.properties`. It's already git-ignored, so **never commit it**.

```properties
storePassword=********
keyPassword=********
keyAlias=secure-edu
storeFile=/home/you/secure-edu-release.jks
```

`app/android/app/build.gradle.kts` is already set up to read this file. It also turns on R8 shrinking and obfuscation and sets `minSdk` to 23 or higher.

### 5.2 Set the identity

- Change `applicationId` and `namespace` in `build.gradle.kts`, and the `MainActivity.kt` package folder, from `com.yourinstitute.secure_edu` to your own ID **before** the first release. You can't change the ID after you publish.
- Set the version in `app/pubspec.yaml` (`version: 1.0.0+1`). Increase `+N` for every upload.
- Set the app icon, for example with `flutter_launcher_icons`.

### 5.3 Build

```bash
cd app
flutter clean && flutter pub get

# Play Store (recommended: needed for Play Integrity / App Check)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
# → build/app/outputs/bundle/release/app-release.aab

# Direct-install APKs (one per CPU architecture, smaller downloads)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  (most phones)
```

Keep `build/symbols/`. You need it to read crash stack traces from obfuscated builds.

### 5.4 Pre-release checklist

- [ ] Release SHA-1/SHA-256 (and the Play App Signing SHA) are added in Firebase. Google Sign-In fails without them.
- [ ] App Check is set to **Enforce** for Cloud Functions in the console after you test a release build.
- [ ] Every Cloudflare video has `requireSignedURLs: true` and MP4 downloads are off.
- [ ] Firestore rules are deployed and `rules-tests` passes.
- [ ] A screenshot and screen recording during playback come out black (Android).
- [ ] A second phone with the same account gets "registered on another device".
- [ ] An unapproved email lands on "Access pending". Running `grant` unlocks it live.
- [ ] Budget alerts are set in Google Cloud Billing and Cloudflare.

### 5.5 Distribute

- **Google Play (recommended):** Play Console → create app → upload `.aab` to **Internal testing** (instant, up to 100 testers) → Closed → Production. Students install from the Play link.
- **Sideload:** share the `arm64-v8a` APK. Note the App Check caveat in step 3.

---

## 6. Cost summary (small coaching institute, ~200 students)

| Item | Monthly |
|---|---|
| Firebase Auth / Firestore / Functions | ~$0–5 (free tiers cover most of it) |
| Cloudflare Stream (100 h library, 3,000 h watched) | ~$30 + ~$180 |
| Google Play developer account | $25 one-time |

At larger viewing volumes, Bunny Stream cuts the delivery line significantly. If leaks become a real problem, VdoCipher adds DRM.
