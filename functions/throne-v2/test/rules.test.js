'use strict';
const {test, before, after} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, deleteDoc} = require('firebase/firestore');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' || process.env.GCLOUD_PROJECT !== 'demo-tini-throne') throw Error('Demo emulator required');
let env, a, b;
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-tini-throne',firestore:{host:'127.0.0.1',port:8080,rules:readFileSync(resolve(__dirname,'../../../firestore.rules'),'utf8')}});
  await env.clearFirestore();
  a = env.authenticatedContext('a').firestore(); b = env.authenticatedContext('b').firestore();
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'users/a'),{tiniBalance:100,walletVersion:2,throneReservedPoints:0,boxReservedPoints:0,walletDebt:0});
    await setDoc(doc(ctx.firestore(),'posts/held'),{uid:'a',isMysteryBox:true,boxOwnedByUid:'b',boxPrice:100});
    await setDoc(doc(ctx.firestore(),'posts/plain'),{uid:'a',description:'old'});
  });
});
after(async()=>env.cleanup());
test('profile edits remain possible, money/reservations/account binding are server-only', async()=>{
  await assertSucceeds(updateDoc(doc(a,'users/a'),{fullName:'New name'}));
  for (const [key,value] of Object.entries({tiniBalance:999,throneReservedPoints:9,boxReservedPoints:9,walletVersion:3,walletDebt:0,purchaseAccountToken:'forged',badge:'diamond'})) {
    // Use a changed value for walletDebt as well.
    await assertFails(updateDoc(doc(a,'users/a'),{[key]:key==='walletDebt'?9:value}));
  }
  await assertFails(deleteDoc(doc(a,'users/a')));
});
test('zero-balance signup allowed; fake balances and profiles for another user denied',async()=>{
  await assertSucceeds(setDoc(doc(b,'users/b'),{tiniBalance:0,fullName:'User',badge:null,badgeEndsAt:null}));
  await assertFails(setDoc(doc(a,'users/victim'),{tiniBalance:0}));
  const c = env.authenticatedContext('c').firestore();
  await assertFails(setDoc(doc(c,'users/c'),{tiniBalance:500}));
});
test('ordinary post editing preserved; box holds cannot be forged, repriced or deleted',async()=>{
  await assertSucceeds(updateDoc(doc(a,'posts/plain'),{description:'new'}));
  await assertFails(updateDoc(doc(a,'posts/held'),{boxPrice:1}));
  await assertFails(updateDoc(doc(a,'posts/held'),{boxOwnedByUid:null}));
  await assertFails(deleteDoc(doc(a,'posts/held')));
  await assertFails(setDoc(doc(a,'posts/fake'),{uid:'a',boxSold:true,boxOwnedByUid:'b'}));
  await assertSucceeds(setDoc(doc(a,'posts/box'),{uid:'a',isMysteryBox:true,boxSold:false,boxOwnedByUid:null,boxPrice:50}));
});
test('clients cannot manufacture purchase queue entries, ledger, holds or receipt delivery',async()=>{
  for (const path of ['users/a/pending_purchases/fake','users/a/transactions/fake','wallet_receipts/fake','box_holds/fake','wallet_config/runtime'])
    await assertFails(setDoc(doc(a,path),{amount:1000}));
});

test('migration maintenance prevents new client profiles from escaping the reviewed inventory',async()=>{
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(),'wallet_config/runtime'),{migrationInProgress:true}));
  const c = env.authenticatedContext('duringMigration').firestore();
  await assertFails(setDoc(doc(c,'users/duringMigration'),{tiniBalance:0}));
  await env.withSecurityRulesDisabled(async ctx => deleteDoc(doc(ctx.firestore(),'wallet_config/runtime')));
});
