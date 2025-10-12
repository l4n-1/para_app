const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

exports.claimBaryaBox = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send({ success: false, message: 'Only POST allowed' });
  }

  try {
    const { deviceId, uid } = req.body || {};
    if (!deviceId || !uid) {
      return res.status(400).send({ success: false, message: 'deviceId and uid required' });
    }

    const boxRef = db.collection('baryaBoxes').doc(deviceId);
    const boxSnap = await boxRef.get();

    if (!boxSnap.exists) {
      return res.status(404).send({ success: false, message: 'Device not found' });
    }

    const boxData = boxSnap.data() || {};

    if (boxData.claimedBy && boxData.claimedBy === uid) {
      await db.collection('users').doc(uid).set({ role: 'tsuperhero' }, { merge: true });
      await db.collection('jeepneys').doc(deviceId).set({
        driverId: uid,
        status: 'inactive',
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
      return res.send({ success: true, message: 'Already claimed by you' });
    }

    if (boxData.claimedBy && boxData.claimedBy !== uid) {
      return res.status(403).send({ success: false, message: 'Device already claimed' });
    }

    const batch = db.batch();
    batch.set(boxRef, {
      claimedBy: uid,
      claimedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    const userRef = db.collection('users').doc(uid);
    batch.set(userRef, { role: 'tsuperhero' }, { merge: true });

    const jeepRef = db.collection('jeepneys').doc(deviceId);
    batch.set(jeepRef, {
      driverId: uid,
      status: 'inactive',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    await batch.commit();

    return res.send({ success: true, message: 'Device claimed successfully, role updated' });
  } catch (err) {
    console.error('claimBaryaBox error:', err);
    return res.status(500).send({ success: false, message: 'Internal server error' });
  }
});