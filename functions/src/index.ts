/**
 * Secure playback backend.
 *
 * `getPlaybackToken` is the ONLY way a client can obtain a playable video
 * URL. Before signing it re-verifies everything server-side, because
 * anything the app checks locally can be bypassed by a modified client:
 *
 *   1. App Check     – request comes from the genuine app on a real device
 *   2. Auth          – caller is signed in with a verified email
 *   3. Subscription  – subscriptions/{email} is active, unexpired and
 *                      covers the requested course
 *   4. Device lock   – account is bound to one install (anti-sharing)
 *
 * It then returns a short-lived Cloudflare Stream signed URL that is
 * useless after it expires and is tied to one specific video.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import jwt from "jsonwebtoken";

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: "asia-south1", maxInstances: 20 });

/** Cloudflare Stream signing key id (`id` returned by POST /stream/keys). */
const STREAM_KEY_ID = defineString("STREAM_KEY_ID");
/** Customer subdomain code, e.g. `abc123` in customer-abc123.cloudflarestream.com. */
const STREAM_CUSTOMER_CODE = defineString("STREAM_CUSTOMER_CODE");
/** Base64 `pem` returned by POST /stream/keys. Stored in Secret Manager. */
const STREAM_KEY_PEM = defineSecret("STREAM_KEY_PEM");

/** Extra validity on top of the video length to allow pausing/seeking. */
const TOKEN_GRACE_SECONDS = 30 * 60;
const TOKEN_MAX_SECONDS = 4 * 60 * 60;

interface PlaybackRequest {
  courseId?: unknown;
  videoId?: unknown;
  deviceId?: unknown;
}

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function requireId(value: unknown, name: string): string {
  if (typeof value !== "string" || !ID_PATTERN.test(value)) {
    throw new HttpsError("invalid-argument", `Invalid ${name}.`);
  }
  return value;
}

export const getPlaybackToken = onCall(
  {
    enforceAppCheck: true,
    secrets: [STREAM_KEY_PEM],
    memory: "256MiB",
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) throw new HttpsError("unauthenticated", "Sign in required.");

    const email = (auth.token.email ?? "").toLowerCase();
    if (!email || auth.token.email_verified !== true) {
      throw new HttpsError("permission-denied", "EMAIL_NOT_VERIFIED");
    }

    const data = (request.data ?? {}) as PlaybackRequest;
    const courseId = requireId(data.courseId, "courseId");
    const videoId = requireId(data.videoId, "videoId");
    const deviceId = requireId(data.deviceId, "deviceId");

    // --- Subscription / entitlement -------------------------------------
    const [subSnap, videoSnap, sourceSnap] = await Promise.all([
      db.doc(`subscriptions/${email}`).get(),
      db.doc(`courses/${courseId}/videos/${videoId}`).get(),
      db.doc(`videoSources/${videoId}`).get(),
    ]);

    const sub = subSnap.data();
    const expiresAt = sub?.expiresAt as Timestamp | undefined;
    const courseIds: string[] = Array.isArray(sub?.courseIds) ? sub.courseIds : [];
    const entitled =
      sub?.status === "active" &&
      (!expiresAt || expiresAt.toMillis() > Date.now()) &&
      (courseIds.includes("*") || courseIds.includes(courseId));
    if (!entitled) {
      throw new HttpsError("permission-denied", "NOT_SUBSCRIBED");
    }

    const source = sourceSnap.data();
    if (!videoSnap.exists || !source || source.courseId !== courseId) {
      throw new HttpsError("not-found", "Video not found.");
    }
    const streamUid = source.streamUid as string;
    const durationSec = Number(videoSnap.get("durationSec") ?? 0);

    // --- Single-device binding ------------------------------------------
    // First successful play binds the account to this install. A different
    // install is refused until an admin clears `boundDeviceId`.
    const userRef = db.doc(`users/${auth.uid}`);
    await db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      const bound = user.get("boundDeviceId") as string | undefined;
      if (bound && bound !== deviceId) {
        throw new HttpsError("permission-denied", "DEVICE_MISMATCH");
      }
      if (!bound) {
        tx.set(
          userRef,
          { boundDeviceId: deviceId, boundAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    });

    // --- Sign a Cloudflare Stream token ---------------------------------
    // Unknown duration (0) falls back to the maximum window.
    const ttl =
      durationSec > 0
        ? Math.min(durationSec + TOKEN_GRACE_SECONDS, TOKEN_MAX_SECONDS)
        : TOKEN_MAX_SECONDS;
    const nowSec = Math.floor(Date.now() / 1000);
    const exp = nowSec + ttl;
    const keyId = STREAM_KEY_ID.value();
    const token = jwt.sign(
      {
        sub: streamUid,
        kid: keyId,
        nbf: nowSec - 30,
        exp,
        // Optional: only allow playback from specific countries.
        // accessRules: [{ type: "ip.geoip.country", action: "allow", country: ["IN"] },
        //               { type: "any", action: "block" }],
      },
      Buffer.from(STREAM_KEY_PEM.value(), "base64").toString("utf8"),
      { algorithm: "RS256", keyid: keyId },
    );

    const url =
      `https://customer-${STREAM_CUSTOMER_CODE.value()}.cloudflarestream.com/` +
      `${token}/manifest/video.m3u8`;

    // Audit trail: lets you spot one account streaming abnormally much.
    await db.collection("playbackLogs").add({
      uid: auth.uid,
      email,
      courseId,
      videoId,
      deviceId,
      at: FieldValue.serverTimestamp(),
    });
    logger.info("playback granted", { uid: auth.uid, courseId, videoId });

    return {
      url,
      expiresAt: exp * 1000,
      watermark: `${email} · ${auth.uid.slice(0, 6)}`,
    };
  },
);
