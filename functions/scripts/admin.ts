/**
 * Admin CLI — the only way subscriptions, catalogue and video sources are
 * written (Firestore rules block all client writes to them).
 *
 * Auth:  gcloud auth application-default login
 *        export GOOGLE_CLOUD_PROJECT=<your-firebase-project-id>
 *
 * Usage (from functions/):
 *   npm run admin -- grant student@gmail.com physics-11,chem-11 365 "Annual"
 *   npm run admin -- grant student@gmail.com '*' 30 "Monthly - all courses"
 *   npm run admin -- revoke student@gmail.com
 *   npm run admin -- reset-device student@gmail.com
 *   npm run admin -- add-course physics-11 1 "Physics Class 11" "NCERT + JEE basics"
 *   npm run admin -- add-chapter physics-11 ch01 1 "Units and Measurement"
 *   npm run admin -- add-video physics-11 ch01 ch01-l01 <cloudflareStreamUid> 1 "Introduction"
 *   npm run admin -- list-subs
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

const DAY_MS = 24 * 60 * 60 * 1000;

async function streamDurationSec(streamUid: string): Promise<number> {
  const account = process.env.CF_ACCOUNT_ID;
  const token = process.env.CF_API_TOKEN;
  if (!account || !token) return 0;
  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${account}/stream/${streamUid}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  const body = (await res.json()) as { result?: { duration?: number } };
  return Math.round(body.result?.duration ?? 0);
}

async function main(): Promise<void> {
  const [cmd, ...args] = process.argv.slice(2);
  switch (cmd) {
    case "grant": {
      const [emailRaw, courses, days, plan] = args;
      if (!emailRaw || !courses || !days) throw new Error("grant <email> <courseIds|*> <days> [plan]");
      const email = emailRaw.trim().toLowerCase();
      await db.doc(`subscriptions/${email}`).set(
        {
          email,
          status: "active",
          plan: plan ?? null,
          courseIds: courses.split(",").map((c) => c.trim()).filter(Boolean),
          startsAt: FieldValue.serverTimestamp(),
          expiresAt: Timestamp.fromMillis(Date.now() + Number(days) * DAY_MS),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      console.log(`Granted ${email} → ${courses} for ${days} days`);
      break;
    }
    case "revoke": {
      const email = args[0]?.trim().toLowerCase();
      if (!email) throw new Error("revoke <email>");
      await db.doc(`subscriptions/${email}`).update({
        status: "revoked",
        updatedAt: FieldValue.serverTimestamp(),
      });
      // Also kill existing sessions so the app signs out promptly.
      const user = await getAuth().getUserByEmail(email).catch(() => null);
      if (user) await getAuth().revokeRefreshTokens(user.uid);
      console.log(`Revoked ${email}`);
      break;
    }
    case "reset-device": {
      const email = args[0]?.trim().toLowerCase();
      if (!email) throw new Error("reset-device <email>");
      const user = await getAuth().getUserByEmail(email);
      await db.doc(`users/${user.uid}`).update({
        boundDeviceId: FieldValue.delete(),
        boundAt: FieldValue.delete(),
      });
      console.log(`Device binding cleared for ${email}; next device to play is bound.`);
      break;
    }
    case "add-course": {
      const [courseId, order, title, description] = args;
      if (!courseId || !order || !title) throw new Error("add-course <courseId> <order> <title> [description]");
      await db.doc(`courses/${courseId}`).set(
        { title, description: description ?? "", order: Number(order), published: true },
        { merge: true },
      );
      console.log(`Course ${courseId} saved`);
      break;
    }
    case "add-chapter": {
      const [courseId, chapterId, order, title] = args;
      if (!courseId || !chapterId || !order || !title) throw new Error("add-chapter <courseId> <chapterId> <order> <title>");
      await db.doc(`courses/${courseId}/chapters/${chapterId}`).set({ title, order: Number(order) });
      console.log(`Chapter ${courseId}/${chapterId} saved`);
      break;
    }
    case "add-video": {
      const [courseId, chapterId, videoId, streamUid, order, ...titleParts] = args;
      const title = titleParts.join(" ");
      if (!courseId || !chapterId || !videoId || !streamUid || !order || !title) {
        throw new Error("add-video <courseId> <chapterId> <videoId> <streamUid> <order> <title>");
      }
      const durationSec = await streamDurationSec(streamUid);
      const batch = db.batch();
      // Public metadata the app lists…
      batch.set(db.doc(`courses/${courseId}/videos/${videoId}`), {
        chapterId,
        title,
        order: Number(order),
        durationSec,
      });
      // …and the private source only the Cloud Function can read.
      batch.set(db.doc(`videoSources/${videoId}`), { courseId, streamUid, provider: "cloudflare" });
      await batch.commit();
      console.log(`Video ${videoId} saved (duration ${durationSec}s)`);
      break;
    }
    case "list-subs": {
      const snap = await db.collection("subscriptions").orderBy("email").get();
      for (const d of snap.docs) {
        const s = d.data();
        const exp = (s.expiresAt as Timestamp | undefined)?.toDate().toISOString().slice(0, 10) ?? "never";
        console.log(`${s.status.padEnd(8)} ${d.id.padEnd(36)} ${String(s.courseIds).padEnd(24)} exp ${exp}`);
      }
      break;
    }
    default:
      console.log("Commands: grant | revoke | reset-device | add-course | add-chapter | add-video | list-subs");
      process.exitCode = 1;
  }
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
