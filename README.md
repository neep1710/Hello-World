# Secure Edu

A secure educational video app for students:

- Flutter (Android/iOS) frontend
- Firebase Auth, Firestore and Cloud Functions backend
- Cloudflare Stream signed-URL video delivery

**Start here → [docs/BLUEPRINT.md](docs/BLUEPRINT.md)**. It covers the stack, why YouTube can't secure paid content, the Firestore schema, setup steps and the APK build.

```
app/            Flutter app: login/register, subscription gate, chapter list, secure player
functions/      getPlaybackToken (signed URLs, device lock, App Check) + admin CLI
firestore.rules Security rules (tested in rules-tests/)
```
