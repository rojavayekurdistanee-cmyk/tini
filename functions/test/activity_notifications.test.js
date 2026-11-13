const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const source = readFileSync(require('node:path').join(__dirname, '../index.js'), 'utf8');
const activitySource = source.slice(source.indexOf('exports.sendActivityNotification ='), source.indexOf('exports.onPostCreated ='));

function fixture(options = {}) {
    const sent = [], removed = [], logs = [];
    const token = 'valid-device-token-0001';
    const activity = { toUid: 'owner', fromUid: 'actor', type: 'like', postId: 'video', text: 'أعجب بمنشورك', ...options.activity };
    const docs = {
        'users/actor': { fullName: 'سارة', profileImg: 'https://example.com/avatar.jpg' },
        'users/owner': { fcmTokens: options.tokens || [token], ...options.receiver },
        'users/owner/notificationSettings/preferences': options.prefs || {},
        'posts/video': { thumbnailUrl: 'https://example.com/thumb.jpg', description: 'وصف الفيديو' },
        'posts/video/comments/comment-1': { text: 'هذا تعليق حقيقي' },
        ...options.docs,
    };
    function ref(path) {
        return {
            id: path.split('/').at(-1),
            collection: name => collection(`${path}/${name}`),
            get: async () => ({ exists: docs[path] != null, id: path.split('/').at(-1), data: () => docs[path], ref: ref(path) }),
            update: async value => removed.push(value),
        };
    }
    function collection(path) {
        return {
            doc: id => ref(`${path}/${id}`),
            where: () => ({ limit: () => ({ get: async () => ({ empty: !options.queryPost, docs: options.queryPost ? [{ id: 'video', exists: true, data: () => docs['posts/video'] }] : [] }) }) }),
        };
    }
    const exports = {};
    vm.runInNewContext(activitySource, {
        exports, onDocumentCreated: (_, handler) => handler,
        db: { collection, doc: ref }, Buffer, setTimeout: resolve => resolve(),
        FieldValue: { arrayRemove: (...tokens) => tokens },
        console: { log: (...value) => logs.push(value), warn: (...value) => logs.push(value), error: (...value) => logs.push(value) },
        getMessaging: () => ({ sendEach: async messages => {
            sent.push(messages);
            if (options.send) return options.send(messages, sent.length);
            return { responses: messages.map(() => ({ success: true })), successCount: messages.length, failureCount: 0 };
        } }),
    });
    return { sent, removed, logs, token, run: () => exports.sendActivityNotification({ id: 'event-unique', params: { activityId: 'activity-1' }, data: { data: () => activity } }) };
}

for (const type of ['like', 'comment', 'follow', 'new_follower', 'new_followers', 'share', 'repost', 'reposts', 'save', 'bookmark', 'favorite', 'saves']) {
    test(`${type}: awaited data-only push with actor, thumbnail, recipient and identity`, async () => {
        const f = fixture({ activity: { type, commentId: 'comment-1' } });
        assert.equal((await f.run()).success, true);
        assert.equal(f.sent.length, 1);
        const message = f.sent[0][0];
        assert.equal(message.notification, undefined);
        assert.equal(message.android.priority, 'high');
        if (['like', 'comment', 'follow', 'new_follower', 'new_followers'].includes(type)) {
            assert.equal(message.apns.payload.aps.alert.body, message.data.body);
            assert.equal(message.apns.headers['apns-push-type'], 'alert');
        } else {
            assert.equal(message.apns.payload.aps.contentAvailable, true);
            assert.equal(message.apns.headers['apns-priority'], '5');
        }
        assert.equal(message.data.avatar, 'https://example.com/avatar.jpg');
        assert.equal(message.data.postImage, 'https://example.com/thumb.jpg');
        assert.equal(message.data.toUid, 'owner');
        assert.equal(message.data.eventId, 'event-unique');
        assert.ok(Object.values(message.data).every(value => typeof value === 'string'));
        if (type === 'comment') assert.match(message.data.body, /هذا تعليق حقيقي/);
    });
}

for (const [type, setting] of [['like', 'likes'], ['comment', 'comments'], ['follow', 'new_followers'], ['share', 'reposts'], ['favorite', 'saves']]) {
    for (const legacy of [false, true]) test(`${type}: respects ${legacy ? 'legacy' : 'current'} server mute`, async () => {
        const f = fixture({ activity: { type }, ...(legacy ? { receiver: { notificationSettings: { [setting]: false } } } : { prefs: { [setting]: false } }) });
        await f.run();
        assert.equal(f.sent.length, 0);
    });
}

test('share/save stay pending until FCM send resolves', async () => {
    for (const type of ['share', 'favorite']) {
        let complete;
        const f = fixture({ activity: { type }, send: () => new Promise(resolve => { complete = resolve; }) });
        let finished = false;
        const running = f.run().then(() => { finished = true; });
        while (!complete) await new Promise(resolve => setImmediate(resolve));
        assert.equal(finished, false);
        complete({ responses: [{ success: true }], successCount: 1, failureCount: 0 });
        await running;
        assert.equal(finished, true);
    }
});

test('deduplicates tokens and sends no more than 500 per batch', async () => {
    const tokens = Array.from({ length: 501 }, (_, index) => `device-token-${index}`);
    const f = fixture({ tokens: [...tokens, tokens[0], '', null, 123] });
    await f.run();
    assert.deepEqual(f.sent.map(batch => batch.length), [500, 1]);
});

test('retries only transient failed tokens and removes permanently invalid tokens', async () => {
    const f = fixture({ tokens: ['success-token-0001', 'transient-token-0002', 'invalid-token-0003'], send: (messages, call) => ({
        successCount: 1, failureCount: call === 1 ? 2 : 0,
        responses: call === 1 ? [{ success: true }, { success: false, error: { code: 'messaging/server-unavailable' } }, { success: false, error: { code: 'messaging/registration-token-not-registered' } }] : [{ success: true }],
    }) });
    assert.equal((await f.run()).success, true);
    assert.equal(f.sent[1].length, 1);
    assert.equal(f.sent[1][0].token, 'transient-token-0002');
    assert.equal(f.removed[0].fcmTokens[0], 'invalid-token-0003');
});

test('transient retry is bounded and reports total failure', async () => {
    const f = fixture({ send: messages => ({ responses: messages.map(() => ({ success: false, error: { code: 'messaging/internal-error' } })) }) });
    assert.equal((await f.run()).success, false);
    assert.equal(f.sent.length, 3);
});

test('canonicalizes old .mp4 post IDs for Flutter audience verification', async () => {
    const f = fixture({ activity: { postId: 'video.mp4' } });
    await f.run();
    assert.equal(f.sent[0][0].data.postId, 'video');
});

test('query fallback also sends canonical post ID', async () => {
    const f = fixture({ activity: { postId: 'legacy-id' }, queryPost: true });
    await f.run();
    assert.equal(f.sent[0][0].data.postId, 'video');
});

test('no post is required for a follower notification', async () => {
    const f = fixture({ activity: { type: 'follow', postId: null } });
    await f.run();
    assert.equal(f.sent[0][0].data.postId, '');
});

test('fallback text is nonempty and oversized previews stay below FCM limit', async () => {
    for (const text of [' ', 'تعليق '.repeat(2000)]) {
        const f = fixture({ activity: { text } });
        await f.run();
        assert.ok(f.sent[0][0].data.body.trim());
        assert.ok(Buffer.byteLength(JSON.stringify(f.sent[0][0].data)) <= 3500);
    }
});

for (const type of ['story_new', 'view', 'story_view', 'following_post', 'people_you_may_know_post', 'message', 'chat', 'private_message']) {
    test(`${type}: preserves existing external notification exclusion`, async () => {
        const f = fixture({ activity: { type } }); await f.run(); assert.equal(f.sent.length, 0);
    });
}

test('self interactions and recipients without tokens stay silent', async () => {
    for (const options of [{ activity: { toUid: 'actor' } }, { tokens: [] }]) {
        const f = fixture(options); await f.run(); assert.equal(f.sent.length, 0);
    }
});
