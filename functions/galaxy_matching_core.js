'use strict';
const {createHash, randomBytes} = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');
const {Timestamp} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');

// Stable skill identifiers; category names are not match keys.
const SKILLS = Object.freeze([
  'language.english', 'language.arabic', 'language.kurdish', 'language.turkish',
  'photography.basics', 'design.graphics', 'coding.basics', 'writing.basics',
  'cooking.basics', 'music.basics', 'video.editing', 'study.math', 'study.science',
]);
const DAY = 86400000;
const token = () => randomBytes(24).toString('hex');
const digest = value => createHash('sha256').update(value).digest('hex');
const pairId = (a, b) => digest(JSON.stringify([a, b].sort()));
const ms = value => value?.toMillis?.() ?? 0;
const at = value => Timestamp.fromMillis(value);
const fail = (code, message) => { throw new HttpsError(code, message); };
function validToken(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{48}$/.test(value)) fail('invalid-argument', 'Invalid request.');
  return value;
}
function birthDay(value) {
  if (typeof value?.toDate === 'function') value = value.toDate();
  if (value instanceof Date) {
    return Number.isFinite(value.getTime()) ? value.toISOString().slice(0, 10) : null;
  }
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:$|T| )/.exec(value.trim());
  if (!match) return null;
  const date = new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === match[0].slice(0, 10)
    ? date.toISOString().slice(0, 10) : null;
}
function ageBand(account, now) {
  const rawBirth = account.birthDate;
  const rawDob = account.dob;
  const birth = rawBirth == null || rawBirth === '' ? null : birthDay(rawBirth);
  if (rawBirth != null && rawBirth !== '' && !birth) return null;
  let canonical = birth;
  if (rawDob != null && rawDob !== '') {
    if (typeof rawDob?.toDate === 'function' || rawDob instanceof Date) {
      const date = typeof rawDob?.toDate === 'function' ? rawDob.toDate() : rawDob;
      // Flutter historically saved DOB as local midnight. The ISO birthDate
      // supplies the calendar day; a timestamp may differ by its timezone offset.
      if (!birth || !Number.isFinite(date.getTime()) ||
          Math.abs(date.getTime() - Date.parse(`${birth}T00:00:00Z`)) > 14 * 3600000) return null;
    } else {
      const dob = birthDay(rawDob);
      if (!dob || (birth && dob !== birth)) return null;
      canonical = dob;
    }
  }
  if (!canonical) return null;
  const today = new Date(now).toISOString().slice(0, 10);
  if (canonical > today || canonical < '1900-01-01') return null;
  let age = Number(today.slice(0, 4)) - Number(canonical.slice(0, 4));
  if (today.slice(5) < canonical.slice(5)) age--;
  return age >= 18 ? 'adult' : 'minor';
}
function restricted(account) {
  const yes = value => value === true || value === 1 || value === '1' || value === 'true';
  const canonical = ['audience_18plus', 'isAdultContent'];
  if (canonical.some(k => Object.hasOwn(account, k))) {
    return canonical.some(k => account[k] != null && ![false, 0, 'false', '0'].includes(account[k]));
  }
  return yes(account.ownerIsAdultContent) || yes(account.ownerAudience18Plus);
}
function eligible(account, pref, now) {
  const band = account && ageBand(account, now);
  return !!(account && pref?.enabled === true && SKILLS.includes(pref.offer) && SKILLS.includes(pref.need) &&
    typeof account.fullName === 'string' && account.fullName.trim() &&
    typeof account.username === 'string' && account.username.trim() &&
    account.isPrivate !== true && account.showInGalaxy !== false && band &&
    (band === 'adult' || !restricted(account)));
}
function complementary(a, b) { return a.offer === b.need && a.need === b.offer; }
function identity(uid, account) {
  return {uid, fullName: account.fullName, username: account.username, profileImg: account.profileImg || ''};
}
const prefsRef = (db, uid) => db.doc(`galaxy_match_preferences/${uid}`);
const inboxRef = (db, uid, id) => db.doc(`galaxy_match_inbox/${uid}/galaxy_match_items/${id}`);
async function readPair(tx, db, a, b, now) {
  const refs = [db.doc(`users/${a}`), db.doc(`users/${b}`), prefsRef(db, a), prefsRef(db, b),
    db.doc(`users/${a}/blocked/${b}`), db.doc(`users/${b}/blocked/${a}`),
    db.doc(`users/${a}/blockedBy/${b}`), db.doc(`users/${b}/blockedBy/${a}`)];
  const docs = await tx.getAll(...refs);
  const [ua, ub, pa, pb] = docs.slice(0, 4).map(d => d.data());
  const contains = (u, id) => ['blocked', 'blockedUsers'].some(k => Array.isArray(u?.[k]) && u[k].includes(id));
  const blocked = docs.slice(4).some(d => d.exists) || contains(ua, b) || contains(ub, a);
  const available = a !== b && !blocked && eligible(ua, pa, now) && eligible(ub, pb, now) &&
    ageBand(ua, now) === ageBand(ub, now) && complementary(pa, pb);
  return {ua, ub, pa, pb, blocked, available};
}
async function quota(tx, db, uid, action, now, max, period) {
  const ref = prefsRef(db, uid).collection('limits').doc(action);
  const doc = await tx.get(ref), data = doc.data();
  const window = Math.floor(now / period);
  const count = data?.window === window ? data.count : 0;
  if (count >= max) fail('resource-exhausted', 'يرجى الانتظار قبل المحاولة مجدداً.');
  return () => tx.set(ref, {window, count: count + 1});
}
function indexData(uid, user, pref, now) {
  const band = ageBand(user || {}, now) || 'unknown';
  const result = {offer: pref.offer, need: pref.need, eligible: eligible(user, pref, now),
    band, rank: parseInt(digest(uid).slice(0, 8), 16) / 0x100000000};
  if (band === 'minor') {
    const birth = birthDay(user.birthDate || user.dob);
    if (birth) result.reviewAt = at(Date.UTC(Number(birth.slice(0, 4)) + 18,
      Number(birth.slice(5, 7)) - 1, Number(birth.slice(8, 10))));
  }
  return result;
}
function writeInvite(tx, db, ref, invite, now, pair) {
  tx.set(ref, invite);
  for (const uid of [invite.sender, invite.recipient]) {
    const other = uid === invite.sender ? invite.recipient : invite.sender;
    const item = {status: invite.status, direction: uid === invite.sender ? 'sent' : 'received',
      offer: uid === invite.sender ? invite.offer : invite.need,
      need: uid === invite.sender ? invite.need : invite.offer,
      createdAt: invite.createdAt, updatedAt: at(now), expiresAt: invite.expiresAt};
    if (invite.purgeAt) item.purgeAt = invite.purgeAt;
    if (invite.status === 'accepted' && pair) {
      item.peer = identity(other, other === invite.sender ? pair.ua : pair.ub);
    }
    // No internal pair IDs, UIDs, source documents or profile data before consent.
    tx.set(inboxRef(db, uid, invite.publicId), item);
  }
}
function terminal(invite, status, now) {
  return {...invite, status, updatedAt: at(now), cooldownUntil: at(now + 7 * DAY), purgeAt: at(now + 30 * DAY)};
}

function createMatching(db, {clock = Date.now} = {}) {
  async function save(uid, input) {
    if (typeof input?.enabled !== 'boolean' || !SKILLS.includes(input.offer) || !SKILLS.includes(input.need)) {
      fail('invalid-argument', 'اختر مهارة وما تحتاجه من القائمة.');
    }
    const now = clock();
    return db.runTransaction(async tx => {
      const [user, old] = await tx.getAll(db.doc(`users/${uid}`), prefsRef(db, uid));
      if (!user.exists) fail('failed-precondition', 'الحساب غير متاح.');
      const spend = await quota(tx, db, uid, 'save', now, 20, 3600000);
      const before = old.data();
      const changed = !before || ['enabled', 'offer', 'need'].some(k => before[k] !== input[k]);
      const pref = {offer: input.offer, need: input.need, enabled: input.enabled,
        version: (before?.version || 0) + (changed ? 1 : 0), updatedAt: at(now)};
      spend(); tx.set(prefsRef(db, uid), pref);
      tx.set(db.doc(`galaxy_match_index/${uid}`), indexData(uid, user.data(), pref, now));
      return {ok: true};
    });
  }
  async function discover(uid) {
    const now = clock();
    const pref = await db.runTransaction(async tx => {
      const [user, prefs] = await tx.getAll(db.doc(`users/${uid}`), prefsRef(db, uid));
      if (!eligible(user.data(), prefs.data(), now)) fail('failed-precondition', 'فعّل المشاركة وتحقق من أهلية حسابك أولاً.');
      const spend = await quota(tx, db, uid, 'discover', now, 10, 3600000);
      spend(); return {...prefs.data(), band: ageBand(user.data(), now)};
    });
    const pivot = parseInt(randomBytes(4).toString('hex'), 16) / 0x100000000;
    const results = [], seen = new Set([uid]);
    let budget = 48;
    for (const wrap of [false, true]) {
      let base = db.collection('galaxy_match_index').where('eligible', '==', true)
        .where('offer', '==', pref.need).where('need', '==', pref.offer).where('band', '==', pref.band)
        .where('rank', '>=', wrap ? 0 : pivot);
      if (wrap) base = base.where('rank', '<', pivot);
      base = base.orderBy('rank');
      let cursor;
      while (budget > 0 && results.length < 3) {
        let query = base.limit(Math.min(12, budget));
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        if (page.empty) break;
        budget -= page.size;
        for (const doc of page.docs) {
          if (seen.has(doc.id)) continue;
          seen.add(doc.id);
          const previewToken = token();
          const result = await db.runTransaction(async tx => {
            const pair = await readPair(tx, db, uid, doc.id, now);
            const invite = (await tx.get(db.doc(`galaxy_match_invites/${pairId(uid, doc.id)}`))).data();
            if (!pair.available || pair.pa.version !== pref.version ||
                (invite && (['pending', 'accepted'].includes(invite.status) || ms(invite.cooldownUntil) > now))) return null;
            tx.set(db.doc(`galaxy_match_previews/${previewToken}`), {viewer: uid, target: doc.id,
              viewerVersion: pair.pa.version, targetVersion: pair.pb.version,
              offer: pref.offer, need: pref.need, expiresAt: at(now + 15 * 60000)});
            return {token: previewToken, offer: pref.offer, need: pref.need, expiresAt: now + 15 * 60000};
          });
          if (result) results.push(result);
          if (results.length === 3) break;
        }
        cursor = page.docs.at(-1);
        if (page.size < 12) break;
      }
    }
    return {results};
  }
  async function request(uid, input) {
    const previewToken = validToken(input?.token), now = clock();
    const previewRef = db.doc(`galaxy_match_previews/${previewToken}`);
    const newPublicId = token();
    const result = await db.runTransaction(async tx => {
      const preview = (await tx.get(previewRef)).data();
      if (!preview || preview.viewer !== uid || ms(preview.expiresAt) <= now) fail('failed-precondition', 'انتهت صلاحية النتيجة. اكتشف توافقاً جديداً.');
      const target = preview.target, ref = db.doc(`galaxy_match_invites/${pairId(uid, target)}`);
      const existing = (await tx.get(ref)).data();
      const pair = await readPair(tx, db, uid, target, now);
      if (!pair.available || pair.pa.version !== preview.viewerVersion || pair.pb.version !== preview.targetVersion) {
        fail('failed-precondition', 'لم يعد هذا التوافق متاحاً.');
      }
      if (existing && ['pending', 'accepted'].includes(existing.status)) return {ok: true};
      if (ms(existing?.cooldownUntil) > now) fail('failed-precondition', 'هذا التوافق غير متاح حالياً.');
      const spend = await quota(tx, db, uid, 'send', now, 10, DAY);
      const invite = {sender: uid, recipient: target, members: [uid, target], publicId: newPublicId,
        offer: pair.pa.offer, need: pair.pa.need, senderVersion: pair.pa.version, recipientVersion: pair.pb.version,
        status: 'pending', createdAt: at(now), expiresAt: at(now + 7 * DAY)};
      spend();
      if (existing) {
        tx.delete(inboxRef(db, existing.sender, existing.publicId));
        tx.delete(inboxRef(db, existing.recipient, existing.publicId));
      }
      writeInvite(tx, db, ref, invite, now);
      return {ok: true};
    });
    return result;
  }
  async function locate(tx, uid, publicId) {
    const found = await tx.get(db.collection('galaxy_match_invites').where('publicId', '==', validToken(publicId)).limit(1));
    const doc = found.docs[0];
    if (!doc || !doc.data().members.includes(uid)) fail('not-found', 'الطلب غير متاح.');
    return doc;
  }
  async function respond(uid, input) {
    if (typeof input?.accept !== 'boolean') fail('invalid-argument', 'Invalid response.');
    const now = clock();
    return db.runTransaction(async tx => {
      const doc = await locate(tx, uid, input.id), invite = doc.data();
      if (invite.recipient !== uid) fail('permission-denied', 'لا يمكنك الرد على هذا الطلب.');
      if (invite.status !== 'pending') return {ok: true, status: invite.status};
      if (ms(invite.expiresAt) <= now) {
        writeInvite(tx, db, doc.ref, terminal(invite, 'expired', now), now);
        return {ok: true, status: 'expired'};
      }
      const pair = await readPair(tx, db, invite.sender, invite.recipient, now);
      if (!pair.available || pair.pa.version !== invite.senderVersion || pair.pb.version !== invite.recipientVersion) {
        writeInvite(tx, db, doc.ref, terminal(invite, 'cancelled', now), now);
        return {ok: true, status: 'cancelled'};
      }
      const next = input.accept ? {...invite, status: 'accepted', updatedAt: at(now)} : terminal(invite, 'rejected', now);
      writeInvite(tx, db, doc.ref, next, now, input.accept ? pair : null);
      return {ok: true, status: next.status};
    });
  }
  async function manage(uid, input) {
    if (!['cancel', 'end'].includes(input?.action)) fail('invalid-argument', 'Invalid action.');
    const now = clock();
    return db.runTransaction(async tx => {
      const doc = await locate(tx, uid, input.id), invite = doc.data();
      if (input.action === 'cancel' && invite.sender !== uid) fail('permission-denied', 'لا يمكنك إلغاء هذا الطلب.');
      if ((input.action === 'cancel' && invite.status !== 'pending') ||
          (input.action === 'end' && invite.status !== 'accepted')) return {ok: true};
      writeInvite(tx, db, doc.ref, terminal(invite, input.action === 'end' ? 'ended' : 'cancelled', now), now);
      return {ok: true};
    });
  }
  async function sync(uid, onlyPeer) {
    const now = clock();
    await db.runTransaction(async tx => {
      const [user, pref] = await tx.getAll(db.doc(`users/${uid}`), prefsRef(db, uid));
      if (!user.exists || !pref.exists) tx.delete(db.doc(`galaxy_match_index/${uid}`));
      else tx.set(db.doc(`galaxy_match_index/${uid}`), indexData(uid, user.data(), pref.data(), now));
    });
    // At most ten outbound requests/day plus inbound requests; page rather than
    // loading the membership set into memory. Repeated events are idempotent.
    let cursor;
    while (true) {
      let query = db.collection('galaxy_match_invites').where('members', 'array-contains', uid)
        .where('status', 'in', ['pending', 'accepted']).orderBy('__name__').limit(50);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      for (const doc of page.docs) {
        if (onlyPeer && !doc.data().members.includes(onlyPeer)) continue;
        await db.runTransaction(async tx => {
          const fresh = await tx.get(doc.ref), invite = fresh.data();
          if (!invite || !['pending', 'accepted'].includes(invite.status)) return;
          const pair = await readPair(tx, db, invite.sender, invite.recipient, now);
          const leftBand = ageBand(pair.ua || {}, now), rightBand = ageBand(pair.ub || {}, now);
          const ageUnsafe = !leftBand || leftBand !== rightBand ||
            (leftBand === 'minor' && (restricted(pair.ua || {}) || restricted(pair.ub || {})));
          const deletedOrBlocked = !pair.ua || !pair.ub || pair.blocked || ageUnsafe;
          const invalidPending = invite.status === 'pending' && (!pair.available ||
            pair.pa?.version !== invite.senderVersion || pair.pb?.version !== invite.recipientVersion);
          if (deletedOrBlocked || invalidPending) {
            writeInvite(tx, db, doc.ref,
              terminal(invite, invite.status === 'accepted' ? 'ended' : 'cancelled', now), now);
          } else if (invite.status === 'accepted') {
            // Read current source identities inside the same transaction as the
            // consent/block checks. Delayed events cannot restore stale data.
            const entries = await tx.getAll(
              inboxRef(db, invite.sender, invite.publicId),
              inboxRef(db, invite.recipient, invite.publicId));
            const peers = [identity(invite.recipient, pair.ub), identity(invite.sender, pair.ua)];
            for (let i = 0; i < entries.length; i++) {
              const item = entries[i].data();
              // Never recreate a removed record or reveal identity in an
              // anonymous/closed inbox item, even if stored data is inconsistent.
              if (item?.status === 'accepted' && !isDeepStrictEqual(item.peer, peers[i])) {
                // Promote a changed item into the live inbox page, including
                // matches previously loaded through pagination.
                tx.update(entries[i].ref, {peer: peers[i], updatedAt: at(now)});
              }
            }
          }
        });
      }
      cursor = page.docs.at(-1);
      if (page.size < 50) break;
    }
    const user = await db.doc(`users/${uid}`).get();
    if (!user.exists) await db.recursiveDelete(prefsRef(db, uid));
  }
  async function cleanup() {
    const now = clock();
    // Birthdays change audience bands even when no profile field is edited.
    const birthdays = await db.collection('galaxy_match_index').where('reviewAt', '<=', at(now)).limit(100).get();
    for (const doc of birthdays.docs) await sync(doc.id);
    const previews = await db.collection('galaxy_match_previews').where('expiresAt', '<=', at(now)).limit(300).get();
    const batch = db.batch(); for (const doc of previews.docs) batch.delete(doc.ref); await batch.commit();
    const pending = await db.collection('galaxy_match_invites').where('status', '==', 'pending').where('expiresAt', '<=', at(now)).limit(100).get();
    for (const doc of pending.docs) await db.runTransaction(async tx => {
      const invite = (await tx.get(doc.ref)).data();
      if (invite?.status === 'pending' && ms(invite.expiresAt) <= now) {
        writeInvite(tx, db, doc.ref, terminal(invite, 'expired', now), now);
      }
    });
    const closed = await db.collection('galaxy_match_invites').where('purgeAt', '<=', at(now)).limit(100).get();
    for (const doc of closed.docs) await db.runTransaction(async tx => {
      const invite = (await tx.get(doc.ref)).data();
      if (!invite || ms(invite.purgeAt) > now || ['pending', 'accepted'].includes(invite.status)) return;
      tx.delete(doc.ref);
      tx.delete(inboxRef(db, invite.sender, invite.publicId)); tx.delete(inboxRef(db, invite.recipient, invite.publicId));
    });
    return {previews: previews.size, expired: pending.size, closed: closed.size};
  }
  return {save, discover, request, respond, manage, sync, cleanup};
}
module.exports = {SKILLS, ageBand, eligible, complementary, createMatching};