// functions/src/index.ts
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

initializeApp();
const db = getFirestore();

/** Mutual like => create deterministic match {a_b}, then delete both likes */
export const onLikeCreate = onDocumentCreated("likes/{likeId}", async (event: any) => {
  const snap = event.data;                     // QueryDocumentSnapshot
  if (!snap) return;

  const { fromUid, toUid } = snap.data() as { fromUid: string; toUid: string };
  if (!fromUid || !toUid || fromUid === toUid) return;

  // Check for reciprocal like
  const reciprocal = await db.collection("likes")
    .where("fromUid", "==", toUid)
    .where("toUid", "==", fromUid)
    .limit(1)
    .get();
  if (reciprocal.empty) return;

  // Create deterministic match doc
  const [a, b] = [fromUid, toUid].sort();
  const matchRef = db.doc(`matches/${a}_${b}`);

  try {
    await matchRef.create({
      participants: [a, b],
      createdAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
    });
  } catch {
    // already exists
  }

  // Clean up likes
  await Promise.all([
    db.collection("likes").doc(snap.id).delete().catch(() => {}),
    reciprocal.docs[0].ref.delete().catch(() => {}),
  ]);
});

/** Block => auto-unmatch if a match exists */
export const onBlockCreate = onDocumentCreated("blocks/{uid}/blocked/{subjectUid}", async (event: any) => {
  const { uid, subjectUid } = event.params as { uid: string; subjectUid: string };
  const [a, b] = [uid, subjectUid].sort();
  const matchRef = db.doc(`matches/${a}_${b}`);
  const m = await matchRef.get();
  if (m.exists) await matchRef.delete().catch(() => {});
});
