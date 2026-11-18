'use strict';
const {FieldPath, FieldValue} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const hash = value => createHash('sha256').update(String(value)).digest('hex');
const own = (data, uid) => (data.uid || data.userId || data.ownerId || data.fromUid) === uid;
const list = value => Array.isArray(value) ? value : [];

// Checkpoints live under the deletion job, never in public application data.
// Each page commits after its idempotent effects, so retries can resume even
// when the account has more data than one function invocation can process.
function createErasure(db, uid, job, storage) {
  const purgeRef = ref => job.collection('purges').doc(hash(ref.path));
  const queuePurge = ref => purgeRef(ref).set({path: ref.path});
  async function purge(ref) {
    // recursiveDelete can remove its parent before a child deletion fails.
    // Keep the path independently so that a retry still finds orphan children.
    await queuePurge(ref);
    await db.recursiveDelete(ref);
  }

  async function walk(name, query, visit) {
    const progress = job.collection('progress').doc(hash(name));
    const saved = (await progress.get()).data();
    if (saved?.done) return;
    let cursor = saved?.cursor;
    while (true) {
      let pageQuery = query.orderBy(FieldPath.documentId()).limit(40);
      if (cursor) pageQuery = pageQuery.startAfter(db.doc(cursor));
      const page = await pageQuery.get();
      if (page.empty) break;
      for (const doc of page.docs) await visit(doc);
      cursor = page.docs.at(-1).ref.path;
      await progress.set({cursor});
    }
    await progress.set({done: true});
  }
  async function removeReaction(ref, parent, counter) {
    await db.runTransaction(async tx => {
      const [reaction, source] = await tx.getAll(ref, parent);
      if (!reaction.exists) return;
      tx.delete(ref);
      if (source.exists && counter) tx.update(parent, {
        [counter]: Math.max(0, Number(source.data()[counter] || 0) - 1)});
    });
  }
  const messages = db.collectionGroup('messages');
  const supportedMessage = doc => ['chat_rooms', 'group_chats', 'users', 'messages'].includes(doc.ref.path.split('/')[0]);
  function mediaKeys(data) {
    const result = new Set();
    // Exclude quoted/forwarded metadata: only actual attachment fields count.
    function collect(value) {
      if (typeof value === 'string') {
        const key = storage.key(value);
        if (key && /^(chat_media|private_media|group_media)\//.test(key)) result.add(key);
      } else if (Array.isArray(value)) value.forEach(collect);
      else if (value && typeof value === 'object') Object.values(value).forEach(collect);
    }
    for (const field of ['mediaUrl', 'thumbnailUrl', 'mediaItems']) collect(data[field]);
    return result;
  }
  function accountAttachment(key) {
    return key.split('/').length >= 4 &&
      ['chat_media', 'private_media', 'group_media'].some(kind => key.startsWith(`${kind}/${uid}/`));
  }
  async function inventoryMessage(doc) {
    if (!supportedMessage(doc)) return;
    const data = doc.data();
    if (data.senderId === uid) await job.collection('messages').doc(hash(doc.ref.path)).set({path: doc.ref.path});
    const batch = db.batch();
    for (const key of mediaKeys(data)) {
      // A retained sender's reference protects a shared attachment from deletion.
      batch.set(job.collection('assets').doc(hash(key)), data.senderId === uid
        ? {key, candidate: true} : {key, retained: true}, {merge: true});
    }
    await batch.commit();
  }
  async function scrubMessage(doc) {
    if (!supportedMessage(doc)) return;
    const data = doc.data();
    if (data.senderId === uid) {
      await queuePurge(doc.ref);
      await db.runTransaction(async tx => {
        const roomRef = doc.ref.parent.parent;
        const current = await tx.get(doc.ref);
        const room = roomRef ? await tx.get(roomRef) : null;
        if (!current.exists) return;
        if (room?.exists && room.data().unreadCount) {
          const group = doc.ref.path.startsWith('group_chats/');
          const recipients = list(room.data()[group ? 'members' : 'participants']).filter(id => id !== uid);
          const updates = [];
          for (const recipient of recipients) {
            const seen = group ? list(current.data().readBy).includes(recipient)
              : current.data().isSeen === true || current.data().seen === true;
            const unread = Number(room.data().unreadCount[recipient]);
            const timestamp = current.data().timestamp;
            if (seen || !(unread > 0) || typeof timestamp?.toMillis !== 'function') continue;
            // Hidden read receipts do not mean "unread". The room counter
            // covers its newest N incoming messages. Include equal timestamps
            // conservatively: only subtract when this entire suffix is unread.
            const suffix = await tx.get(doc.ref.parent
              .where('timestamp', '>=', timestamp)
              .where('senderId', '!=', recipient)
              .orderBy('timestamp', 'desc').orderBy('senderId', 'asc').count());
            if (suffix.data().count <= unread)
              updates.push(new FieldPath('unreadCount', recipient), unread - 1);
          }
          if (updates.length) tx.update(roomRef, ...updates);
        }
        tx.delete(doc.ref);
      });
      await purge(doc.ref);
      return;
    }
    await db.runTransaction(async tx => {
      const current = await tx.get(doc.ref);
      if (!current.exists) return;
      const value = current.data(), patch = {};
      const reply = value.replyTo;
      if (reply) {
        const id = reply.messageId || reply.id;
        const quoted = id ? await tx.get(job.collection('messages').doc(hash(`${doc.ref.parent.path}/${id}`))) : null;
        if (reply.senderId === uid || quoted?.exists) patch.replyTo = FieldValue.delete();
      }
      for (const field of ['readBy', 'deliveredTo', 'viewedBy', 'deletedFor']) {
        if (Array.isArray(value[field]) && value[field].includes(uid)) patch[field] = value[field].filter(id => id !== uid);
      }
      // Forwarding private media keeps its URL, not sourceOwnerUid. Recognize
      // the canonical uploader namespace before that uploader's files are purged.
      const items = list(value.mediaItems);
      const keptItems = items.filter(item => ![...mediaKeys({mediaItems: [item]})].some(accountAttachment));
      const removedItems = keptItems.length !== items.length;
      if (removedItems) patch.mediaItems = keptItems;
      const removedMain = accountAttachment(storage.key(value.mediaUrl) || '');
      if (removedMain) patch.mediaUrl = FieldValue.delete();
      const removedThumbnail = accountAttachment(storage.key(value.thumbnailUrl) || '');
      if (removedThumbnail) patch.thumbnailUrl = FieldValue.delete();
      const removedAttachment = (removedMain || removedItems) && keptItems.length === 0;
      const sourceId = value.sourcePostId || value.postId;
      const removedPost = sourceId ? await tx.get(job.collection('posts').doc(hash(String(sourceId)))) : null;
      if (removedAttachment || value.sourceOwnerUid === uid || removedPost?.exists ||
          (value.type === 'profile_share' && [value.profileUid, value.sharedUid, value.uid].includes(uid))) {
        // Keep the other sender's message, without the deleted profile snapshot.
        for (const key of Object.keys(value)) if (!['senderId','senderName','senderImg','timestamp','type','isSeen','isDelivered','seen','readBy','deliveredTo','viewedBy','deletedFor'].includes(key)) patch[key] = FieldValue.delete();
        patch.type = 'text'; patch.text = 'حُذف المحتوى المشار إليه';
      }
      if (Object.keys(patch).length) tx.update(doc.ref, patch);
    });
  }
  async function cleanPost(doc) {
    const data = doc.data();
    if (own(data, uid)) {
      await job.collection('posts').doc(hash(doc.id)).set({id: doc.id});
      await purge(doc.ref);
      return;
    }
    await db.runTransaction(async tx => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists) return;
      const current = fresh.data(), attribution = {};
      if (current.duetOriginalOwnerId === uid) {
        attribution.duetOriginalOwnerId = ''; attribution.duetFrom = '';
        attribution.originalAuthorName = 'حساب محذوف'; attribution.originalUsername = '';
      }
      if (list(current.mentions).some(value => value === uid || value?.uid === uid))
        attribution.mentions = current.mentions.filter(value => value !== uid && value?.uid !== uid);
      if (Object.keys(attribution).length) tx.update(doc.ref, attribution);
    });
    await removeReaction(doc.ref.collection('likes').doc(uid), doc.ref, 'likesCount');
    await removeReaction(db.doc(`users/${uid}/favorites/${doc.id}`), doc.ref, 'favoritesCount');
    await walk(`comments:${doc.id}`, doc.ref.collection('comments'), async comment => {
      if (comment.data().uid === uid) {
        // Reparent other people's replies before removing the author's comment.
        await walk(`replies:${comment.ref.path}`, doc.ref.collection('comments').where('parentId', '==', comment.id),
          reply => reply.ref.update({parentId: null}));
        await queuePurge(comment.ref);
        await removeReaction(comment.ref, doc.ref, 'comments');
        await purge(comment.ref);
      } else {
        await removeReaction(comment.ref.collection('likedBy').doc(uid), comment.ref, 'likes');
        await removeReaction(comment.ref.collection('dislikedBy').doc(uid), comment.ref, 'dislikes');
      }
    });
  }
  async function cleanUser(doc) {
    if (doc.id === uid) return;
    await removeReaction(doc.ref.collection('followers').doc(uid), doc.ref, 'followers');
    await removeReaction(doc.ref.collection('following').doc(uid), doc.ref, 'following');
    for (const col of ['blocked', 'blockedBy', 'blockedChannels', 'hiddenSuggestions', 'visits'])
      await purge(doc.ref.collection(col).doc(uid));
    for (const col of ['feed', 'friendsFeed', 'favorites', 'sharedPosts', 'likedPosts', 'watchHistory']) {
      await walk(`user:${doc.id}:${col}`, doc.ref.collection(col), async item => {
        const data = item.data(), id = data.postId || data.originalPostId || item.id;
        if (own(data, uid) || (await job.collection('posts').doc(hash(id)).get()).exists)
          await purge(item.ref);
      });
    }
  }
  async function cleanGroup(doc, group) {
    await db.runTransaction(async tx => {
      const source = await tx.get(doc.ref);
      if (!source.exists) return;
      const value = source.data(), patch = {};
      const memberField = group ? 'members' : 'participants';
      const members = list(value[memberField]).filter(id => id !== uid);
      if (list(value[memberField]).includes(uid) && !members.length) {
        const remaining = await tx.get(doc.ref.collection('messages').limit(1));
        if (remaining.empty) {
          if (group) tx.set(job.collection('groups').doc(hash(doc.id)), {id: doc.id});
          tx.set(purgeRef(doc.ref), {path: doc.ref.path});
          tx.delete(doc.ref);
          return;
        }
      }

      if (group && list(value[memberField]).includes(uid)) patch[memberField] = members;
      // Keep the other participant's history compatible with the two-person
      // room schema, but erase the deleted participant's identity snapshot.
      for (const field of ['admins', 'moderators', 'archivedBy', 'banned']) {
        if (list(value[field]).includes(uid)) patch[field] = value[field].filter(id => id !== uid);
      }
      for (const field of ['participantsInfo','unreadCount','deletedFor','muted','pinned','pinnedAt','restricted','canSendMore','typing','lastRead']) {
        if (value[field] && Object.hasOwn(value[field], uid)) patch.__nested = true;
      }
      if (group && value.createdBy === uid) {
        const next = list(value.admins).find(id => members.includes(id)) || members[0] || '';
        patch.createdBy = next;
        if (next) patch.admins = [...new Set([...list(value.admins).filter(id => id !== uid), next])];
      }
      // Clear previews of removed messages; retain previews from other senders.
      if (value.lastMessageSenderId === uid) {
        patch.lastMessage = ''; patch.lastMessageSenderId = '';
      }
      if (Object.keys(patch).length) {
        // Use FieldPath objects so UIDs containing dots are not split into paths.
        const updates = [];
        for (const [key, val] of Object.entries(patch)) {
          if (key === '__nested') continue;
          if (!key.includes('.')) updates.push(new FieldPath(key), val);
        }
        for (const field of ['participantsInfo','unreadCount','deletedFor','muted','pinned','pinnedAt','restricted','canSendMore','typing','lastRead'])
          if (value[field] && Object.hasOwn(value[field], uid)) updates.push(new FieldPath(field, uid),
            !group && field === 'participantsInfo' ? {name: 'حساب محذوف', profileImg: '', isFriend: false} : FieldValue.delete());
        if (updates.length) tx.update(doc.ref, ...updates);
      }
    });
  }
  async function run() {
    await walk('posts', db.collection('posts'), cleanPost);
    await walk('message-inventory', messages, inventoryMessage);
    await walk('messages', messages, scrubMessage);
    await walk('legacy-videos', db.collection('videos'), async doc => { if (own(doc.data(), uid)) await purge(doc.ref); });
    // Feed copies outside users also contain author snapshots.
    await walk('feed-copies', db.collectionGroup('posts'), async doc => {
      if (doc.ref.path.split('/').length === 2) return;
      const id = doc.data().originalPostId || doc.id;
      if (own(doc.data(), uid) || (await job.collection('posts').doc(hash(id)).get()).exists)
        await purge(doc.ref);
    });
    await walk('users', db.collection('users'), cleanUser);
    // Story parent documents are often absent: the app writes items directly.
    await walk('story-items', db.collectionGroup('items'), async item => {
      const parts = item.ref.path.split('/');
      if (parts[0] !== 'stories' || parts.length !== 4) return;
      if (parts[1] === uid) { await purge(item.ref); return; }
      await removeReaction(item.ref.collection('likes').doc(uid), item.ref, 'likesCount');
      await item.ref.collection('views').doc(uid).delete();
      if (list(item.data().views).includes(uid)) await item.ref.update({views: FieldValue.arrayRemove(uid)});
    });
    await purge(db.doc(`stories/${uid}`));
    await walk('private-rooms', db.collection('chat_rooms'), doc => cleanGroup(doc, false));
    await walk('groups', db.collection('group_chats'), doc => cleanGroup(doc, true));
    for (const col of ['activities', 'group_invites', 'follow_requests', 'userInteractions', 'archived_users']) {
      await walk(col, db.collection(col), async doc => {
        const data = doc.data();
        if ([data.uid,data.userId,data.fromUid,data.toUid,data.senderId,data.receiverId,data.followerId,data.followedId,data.fromUserId,data.toUserId].includes(uid) || (col === 'archived_users' && doc.id === uid) ||
          (data.postId && (await job.collection('posts').doc(hash(String(data.postId))).get()).exists))
          await purge(doc.ref);
      });
    }
    await walk('match-previews', db.collection('galaxy_match_previews'), async doc => {
      if ([doc.data().viewer, doc.data().target].includes(uid)) await doc.ref.delete();
    });
    await walk('match-invites', db.collection('galaxy_match_invites'), async doc => {
      const data = doc.data();
      if (!list(data.members).includes(uid)) return;
      for (const member of data.members) if (data.publicId)
        await db.doc(`galaxy_match_inbox/${member}/galaxy_match_items/${data.publicId}`).delete();
      await doc.ref.delete();
    });
    const account = (await job.get()).data();
    if (account.accountEmail) await walk('mail', db.collection('mail'), async doc => {
      const to = doc.data().to;
      if ((doc.data().ownerUid === uid || to === account.accountEmail || list(to).includes(account.accountEmail)) &&
          doc.createTime.toMillis() <= account.requestedAt.toMillis()) await purge(doc.ref);
    });
    // Financial receipt/idempotency keys must survive to prevent replaying an
    // already credited purchase. Remove public identity snapshots, not amounts
    // or shared auction results belonging to other users.
    for (const col of ['throne_bids', 'throne_reigns', 'throne_ledger']) {
      await walk(`financial-identity:${col}`, db.collection(col), async doc => {
        if (doc.data().uid !== uid) return;
        const patch = {};
        for (const field of ['name','fullName','username','avatar','profileImg','email','phone','phoneNumber'])
          if (Object.hasOwn(doc.data(), field)) patch[field] = FieldValue.delete();
        if (Object.keys(patch).length) await doc.ref.update(patch);
      });
    }
    await walk('auction-identity', db.collectionGroup('competitors'), async doc => {
      if (doc.ref.path.split('/')[0] !== 'throne_auctions' || doc.id !== uid) return;
      await doc.ref.update({name: FieldValue.delete(), avatar: FieldValue.delete()});
    });
    // Remove only the closed user's inactive wallet/entitlement data. Shared
    // purchase receipts and immutable financial ledgers retain anti-replay IDs.
    for (const col of ['throne_wallets', 'throne_entitlements', 'throne_requests'])
      await purge(db.doc(`${col}/${uid}`));
    await db.doc(`galaxy_match_index/${uid}`).delete();
    await purge(db.doc(`galaxy_match_preferences/${uid}`));
    await purge(db.doc(`galaxy_match_inbox/${uid}`));
    await purge(db.doc(`forYouFeed/${uid}`));
    await purge(db.doc(`users/${uid}`));
    await db.doc(`public_profiles/${uid}`).delete();
    await walk('media', job.collection('assets'), async doc => {
      const data = doc.data();
      if (data.candidate && !data.retained) await storage.remove(data.key);
    });
    await walk('empty-group-images', job.collection('groups'), doc => storage.removeGroup(doc.data().id));
    await storage.removeOwned(uid);
    await walk('retry-partial-purges', job.collection('purges'), doc => db.recursiveDelete(db.doc(doc.data().path)));
    // Firestore TTL does not cascade into subcollections.
    for (const col of ['progress', 'assets', 'messages', 'posts', 'groups', 'purges']) await db.recursiveDelete(job.collection(col));
  }
  return {run};
}
module.exports = {createErasure};
