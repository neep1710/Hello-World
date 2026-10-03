// Run: cd rules-tests && npm install && npm test   (needs Java for the emulator)
import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, updateDoc, collection, getDocs, query, where, orderBy,
  serverTimestamp,
} from "firebase/firestore";

let env;
const alice = { email: "alice@example.com", email_verified: true };

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-secure-edu",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "subscriptions/alice@example.com"), { status: "active", courseIds: ["*"] });
    await setDoc(doc(db, "subscriptions/bob@example.com"), { status: "active", courseIds: ["*"] });
    await setDoc(doc(db, "courses/c1"), { title: "C1", published: true, order: 1 });
    await setDoc(doc(db, "courses/c2"), { title: "Draft", published: false, order: 2 });
    await setDoc(doc(db, "courses/c1/videos/v1"), { title: "V1", chapterId: "ch1", order: 1 });
    await setDoc(doc(db, "videoSources/v1"), { streamUid: "secret", courseId: "c1" });
    await setDoc(doc(db, "users/alice"), { name: "Alice", email: alice.email, phone: "" });
  });
});

const as = (uid, token) => env.authenticatedContext(uid, token).firestore();

test("student reads own subscription only", async () => {
  const db = as("alice", alice);
  await assertSucceeds(getDoc(doc(db, "subscriptions/alice@example.com")));
  await assertFails(getDoc(doc(db, "subscriptions/bob@example.com")));
  await assertFails(getDocs(collection(db, "subscriptions")));
});

test("unverified email cannot read subscription or catalogue", async () => {
  const db = as("alice", { ...alice, email_verified: false });
  await assertFails(getDoc(doc(db, "subscriptions/alice@example.com")));
  await assertFails(getDoc(doc(db, "courses/c1/videos/v1")));
});

test("student cannot grant themselves a subscription", async () => {
  const db = as("alice", alice);
  await assertFails(setDoc(doc(db, "subscriptions/alice@example.com"), { status: "active", courseIds: ["*"] }));
});

test("video sources are never readable", async () => {
  await assertFails(getDoc(doc(as("alice", alice), "videoSources/v1")));
});

test("only published courses are listable", async () => {
  const db = as("alice", alice);
  await assertSucceeds(getDocs(query(collection(db, "courses"), where("published", "==", true), orderBy("order"))));
  await assertFails(getDocs(collection(db, "courses")));
  await assertFails(getDoc(doc(db, "courses/c2")));
});

test("profile: editable fields only, device binding locked", async () => {
  const db = as("alice", alice);
  await assertSucceeds(updateDoc(doc(db, "users/alice"), { name: "Alice B", phone: "123", updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, "users/alice"), { boundDeviceId: "x", updatedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(as("bob", { email: "bob@example.com", email_verified: true }), "users/alice")));
});

test("profile create must match token email", async () => {
  const db = as("carol", { email: "carol@example.com", email_verified: false });
  await assertFails(setDoc(doc(db, "users/carol"), { name: "C", email: "alice@example.com", phone: "", createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(db, "users/carol"), { name: "C", email: "carol@example.com", phone: "", createdAt: serverTimestamp() }));
});
