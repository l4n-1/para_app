const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const rtdb = admin.database();

exports.claimBaryaBox = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send({ success: false, message: 'Only POST allowed' });
  }

  try {
    const { deviceId, uid } = req.body || {};
    if (!deviceId || !uid) {
      return res.status(400).send({ success: false, message: 'deviceId and uid required' });
    }

    // Example deviceId: "box-0001"
    const boxRef = db.collection('baryaBoxes').doc(deviceId);
    const boxSnap = await boxRef.get();

    if (!boxSnap.exists) {
      return res.status(404).send({ success: false, message: 'BaryaBox not found' });
    }

    const boxData = boxSnap.data() || {};

    // If already claimed by same user
    if (boxData.claimedBy && boxData.claimedBy === uid) {
      return res.send({ success: true, message: 'Already claimed by you' });
    }

    // If claimed by someone else
    if (boxData.claimedBy && boxData.claimedBy !== uid) {
      return res.status(403).send({ success: false, message: 'Device already claimed' });
    }

    // Auto map: box-0001 → ESP32_TRACKER_01
    const boxNumber = deviceId.match(/\d+/)?.[0] || '001';
    const trackerId = `ESP32_TRACKER_${boxNumber}`;

    // Verify that RTDB tracker exists
    const trackerRef = rtdb.ref(`devices/${trackerId}`);
    const trackerSnap = await trackerRef.once('value');
    if (!trackerSnap.exists()) {
      return res.status(404).send({
        success: false,
        message: `No tracker found in RTDB for ${trackerId}`
      });
    }

    // Batch Firestore updates
    const batch = db.batch();
    const userRef = db.collection('users').doc(uid);
    const jeepRef = db.collection('jeepneys').doc(deviceId);

    batch.set(boxRef, {
      claimedBy: uid,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      trackerId: trackerId
    }, { merge: true });

    batch.set(userRef, { role: 'tsuperhero' }, { merge: true });

    batch.set(jeepRef, {
      driverId: uid,
      trackerId: trackerId,
      status: 'inactive',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    await batch.commit();

    // 🔗 Bind to RTDB: add a reference back to Firestore
    await trackerRef.update({
      boundBoxId: deviceId,
      driverUid: uid,
      boundAt: admin.database.ServerValue.TIMESTAMP
    });

    return res.send({
      success: true,
      message: `BaryaBox ${deviceId} bound to ${trackerId} and claimed successfully.`
    });
  } catch (err) {
    console.error('claimBaryaBox error:', err);
    return res.status(500).send({ success: false, message: 'Internal server error' });
  }
});
