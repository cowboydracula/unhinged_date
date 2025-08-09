// functions/src/index.ts
import * as admin from 'firebase-admin';
import { onCall, CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2/options';
import * as logger from 'firebase-functions/logger';

admin.initializeApp();
const db = admin.firestore();

// Gen2 global opts
setGlobalOptions({
  region: 'us-central1',
  memory: '256MiB',
  cpu: 1,
  maxInstances: 3,
  concurrency: 80,
});

type FeedInput = {
  limit?: number;
  cursorUpdatedAt?: number | null;
};

type CardOut = {
  uid: string;
  updatedAt: number | null;
  profile: Record<string, unknown>;
};

type FeedOutput = {
  cards: CardOut[];
  nextCursorUpdatedAt: number | null;
  hasMore: boolean;
};

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const tsFromMillis = (m: number) => admin.firestore.Timestamp.fromMillis(m);
const toMillis = (ts: admin.firestore.Timestamp | null | undefined) =>
  ts ? ts.toMillis() : null;

export const getFeed = onCall<FeedInput>((async (req: CallableRequest<FeedInput>): Promise<FeedOutput> => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required');

  const limit = clamp((req.data?.limit ?? 25) | 0, 1, 50);
  const cursorMs = req.data?.cursorUpdatedAt ?? null;

  // 1) Gather exclusion sets
  logger.info('[getFeed] stage=blockedByMe');
  const blockedByMe = new Set<string>();
  try {
    const qs = await db.collection('blocks').doc(uid).collection('blocked').select('subjectUid').get();
    qs.docs.forEach(d => {
      const s = (d.get('subjectUid') as string | undefined) ?? d.id;
      if (s) blockedByMe.add(s);
    });
  } catch (e) {
    logger.warn('[getFeed] blockedByMe failed, continuing', e as Error);
  }

  logger.info('[getFeed] stage=blockedMe');
  const blockedMe = new Set<string>();
  try {
    // May need CG index the first time; if it fails, we proceed empty.
    const qs = await db.collectionGroup('blocked').where('subjectUid', '==', uid).select('blockerUid').get();
    qs.docs.forEach(d => {
      const b = (d.get('blockerUid') as string | undefined) ?? d.ref.parent.parent?.id;
      if (b) blockedMe.add(b);
    });
  } catch (e) {
    logger.warn('[getFeed] blockedMe (collectionGroup) failed, treating as empty', e as Error);
  }

  logger.info('[getFeed] stage=liked');
  const liked = new Set<string>();
  try {
    const qs = await db.collection('likes').where('fromUid', '==', uid).select('toUid').get();
    qs.docs.forEach(d => {
      const t = d.get('toUid') as string | undefined;
      if (t) liked.add(t);
    });
  } catch (e) {
    logger.warn('[getFeed] liked failed, continuing', e as Error);
  }

  logger.info('[getFeed] stage=matches');
  const matched = new Set<string>();
  try {
    const qs = await db.collection('matches').where('participants', 'array-contains', uid).select('participants').get();
    qs.docs.forEach(d => {
      const arr = d.get('participants') as string[] | undefined;
      if (Array.isArray(arr)) arr.forEach(p => { if (p !== uid) matched.add(p); });
    });
  } catch (e) {
    logger.warn('[getFeed] matches failed, continuing', e as Error);
  }

  const blacklist = new Set<string>([uid, ...blockedByMe, ...blockedMe, ...liked, ...matched]);

  // 2) Profiles query WITHOUT composite-index requirements:
  //    only orderBy('updatedAt') then filter in memory.
  logger.info('[getFeed] stage=profiles');
  const overfetch = Math.min(limit * 3, 90);

  let q = db.collection('profiles')
    .orderBy('updatedAt', 'desc')
    .limit(overfetch);

  if (typeof cursorMs === 'number' && cursorMs > 0) {
    q = q.startAfter(tsFromMillis(cursorMs));
  }

  const snap = await q.get();

  // Build cards and compute next cursor
  const cards: CardOut[] = [];
  for (const d of snap.docs) {
    const id = d.id;
    if (blacklist.has(id)) continue;

    const data = d.data() as Record<string, unknown>;
    // Filter in memory to avoid composite index
    const hide = !!data['hideMode'];
    const onboarded = !!data['onboardingCompleted'];
    if (hide || !onboarded) continue;

    cards.push({
      uid: id,
      updatedAt: toMillis(data['updatedAt'] as admin.firestore.Timestamp | null),
      profile: data,
    });

    if (cards.length >= limit) break;
  }

  // Cursor & hasMore (based on raw query, not post-filter count)
  const last = snap.docs.at(-1);
  const nextCursorUpdatedAt =
    last ? toMillis((last.data() as any)['updatedAt'] as admin.firestore.Timestamp | null) : null;

  const hasMore = snap.size === overfetch;

  return {
    cards,
    nextCursorUpdatedAt,
    hasMore,
  };
}) as any);
