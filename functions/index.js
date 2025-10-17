const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();
const rtdb = admin.database();

exports.claimBaryaBox = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send({ success: false, message: "Only POST allowed" });
  }

  try {
    let body = req.body;

    // 🧩 Parse body if sent as raw JSON string
    if (typeof body === "string") {
      try {
        body = JSON.parse(body);
      } catch (err) {
        console.warn("⚠️ Invalid JSON body:", body);
        return res.status(400).send({ success: false, message: "Invalid JSON body" });
      }
    }

    const deviceId = (body.deviceId || body.device_id || "").trim();
    const uid = (body.uid || "").trim();

    if (!deviceId || !uid) {
      return res.status(400).send({ success: false, message: "deviceId and uid required" });
    }

    const normalizedId = deviceId.toLowerCase();

    // 🔍 Get or create Firestore doc for the box
    const boxRef = db.collection("baryaBoxes").doc(normalizedId);
    const boxSnap = await boxRef.get();

    if (!boxSnap.exists) {
      await boxRef.set({
        deviceId: normalizedId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "unclaimed",
      });
      console.log(`✨ Auto-created new BaryaBox doc: ${normalizedId}`);
    }

    const boxData = (await boxRef.get()).data() || {};

    // 👀 Already claimed?
    if (boxData.claimedBy && boxData.claimedBy === uid) {
      return res.send({ success: true, message: "Already claimed by you" });
    }

    if (boxData.claimedBy && boxData.claimedBy !== uid) {
      return res.status(403).send({ success: false, message: "Device already claimed" });
    }

    // 🧮 Auto-map: box-0001 → ESP32_TRACKER_0001
    const boxNumber = normalizedId.match(/\d+/)?.[0]?.padStart(4, "0") || "0001";
    const trackerId = `ESP32_TRACKER_${boxNumber}`;

    // 🔗 Check if RTDB tracker exists
    const trackerRef = rtdb.ref(`devices/${trackerId}`);
    const trackerSnap = await trackerRef.once("value");

    if (!trackerSnap.exists()) {
      return res.status(404).send({
        success: false,
        message: `No tracker found in RTDB for ${trackerId}`,
      });
    }

    // ✍️ Firestore batch updates
    const batch = db.batch();
    const userRef = db.collection("users").doc(uid);
    const jeepRef = db.collection("jeepneys").doc(normalizedId);

    // ✅ Update BaryaBox doc
    batch.set(
      boxRef,
      {
        claimedBy: uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        trackerId,
        status: "claimed",
      },
      { merge: true }
    );

    // ✅ Update User doc (add role + boxClaimed)
    batch.set(
      userRef,
      {
        role: "tsuperhero",
        boxClaimed: normalizedId,
      },
      { merge: true }
    );

    // ✅ Update Jeepney doc
    batch.set(
      jeepRef,
      {
        driverId: uid,
        trackerId,
        status: "inactive",
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await batch.commit();

    // ✅ Update RTDB tracker binding
    await trackerRef.update({
      boundBoxId: normalizedId,
      driverUid: uid,
      boundAt: admin.database.ServerValue.TIMESTAMP,
    });

    // ✅ Return success with tracker name
    return res.send({
      success: true,
      message: `✅ BaryaBox ${normalizedId} successfully bound to tracker ${trackerId}.`,
    });
  } catch (err) {
    console.error("❌ claimBaryaBox error:", err);
    return res.status(500).send({ success: false, message: "Internal server error" });
  }
});
