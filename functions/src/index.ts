// functions/src/index.ts
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";

admin.initializeApp();
setGlobalOptions({ region: "us-central1" }); // keep <=10 max instances default

const db = admin.firestore();

type Cursor = { updatedAt: number };

function toMillis(ts: admin.firestore.Timestamp | null | undefined) {
  return ts ? ts.toMillis() : 0;
}

export const getFeed = onCall<{ limit?: number; cursor?: Cursor }>(
  { cors: true },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const limit = Math.max(1, Math.min(50, Number(req.data?.limit ?? 25)));
    const pageLimit = Math.min(150, limit * 3);
    const cursor = req.data?.cursor as Cursor | undefined;

    // Build exclusion sets (server-side; client never sees who blocked whom)
    const [blockedByMeSnap, blockedMeSnap, likedSnap, matchesSnap] =
      await Promise.all([
        db.collection("blocks").doc(uid).collection("blocked").get(),
        db.collectionGroup("blocked").where("subjectUid", "==", uid).get(),
        db.collection("likes").where("fromUid", "==", uid).get(),
        db.collectionGroup("matches").where("members", "array-contains", uid).get(),
      ]);

    const blockedByMe = new Set(blockedByMeSnap.docs.map((d) => d.id));
    const blockedMe = new Set(
      blockedMeSnap.docs
        .map((d) => (d.get("blockerUid") as string) ?? d.ref.parent.parent?.id ?? "")
        .filter(Boolean)
    );
    const liked = new Set(
      likedSnap.docs.map((d) => String(d.get("toUid") ?? "")).filter(Boolean)
    );
    const matched = new Set<string>();
    for (const d of matchesSnap.docs) {
      const members: string[] = d.get("members") ?? d.get("participants") ?? [];
      for (const m of members) matched.add(String(m));
    }
    matched.delete(uid);

    // Primary query: ONLY equality on onboardingCompleted + orderBy(updatedAt desc)
    // We filter hideMode client-side here to avoid a composite index requirement.
    let q = db
      .collection("profiles")
      .where("onboardingCompleted", "==", true)
      .orderBy("updatedAt", "desc")
      .limit(pageLimit);

    // Cursor only on updatedAt (safe; may duplicate a couple docs across pages, acceptable)
    if (cursor?.updatedAt) {
      q = q.startAfter(admin.firestore.Timestamp.fromMillis(cursor.updatedAt));
    }

    const items: any[] = [];
    let nextCursor: Cursor | undefined;

    const runPage = async () => {
      const snap = await q.get();

      for (const d of snap.docs) {
        const id = d.id;
        if (id === uid) continue;

        const data = d.data() ?? {};
        const updated = data.updatedAt as admin.firestore.Timestamp | null | undefined;
        if (!updated) continue; // require updatedAt to keep pagination safe

        // extra filters (no index needed)
        if (data.hideMode === true) continue;

        // block/like/match exclusions
        if (blockedByMe.has(id) || blockedMe.has(id) || liked.has(id) || matched.has(id)) continue;

        const photos: string[] = Array.isArray(data.photos) ? data.photos : [];
        const name = String(data.displayName ?? "").trim();
        if (!name || photos.length === 0) continue;

        items.push({
          id,
          displayName: name,
          bio: String(data.bio ?? ""),
          photos,
          soberDate: data.soberDate ?? null,
          updatedAt: updated.toMillis(),
        });
        if (items.length === limit) break;
      }

      if (snap.docs.length > 0) {
        const last = snap.docs[snap.docs.length - 1];
        const u = last.get("updatedAt") as admin.firestore.Timestamp | null | undefined;
        if (u) nextCursor = { updatedAt: u.toMillis() };
      }

      return snap.docs.length;
    };

    try {
      let fetched = await runPage();
      // Overfetch a couple of pages to hit the limit after filtering
      let guard = 0;
      while (items.length < limit && fetched === pageLimit && guard++ < 2 && nextCursor) {
        q = db
          .collection("profiles")
          .where("onboardingCompleted", "==", true)
          .orderBy("updatedAt", "desc")
          .startAfter(admin.firestore.Timestamp.fromMillis(nextCursor.updatedAt))
          .limit(pageLimit);
        fetched = await runPage();
      }
    } catch (err: any) {
      console.error("getFeed failed:", err?.message || err, err);
      throw new HttpsError("internal", err?.message ?? "getFeed crashed");
    }

    return { items, nextCursor, hasMore: Boolean(nextCursor) };
  }
);
