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

    // Diagnostic: log incoming request briefly (avoid logging sensitive tokens)
    console.log('🔔 claimBaryaBox invoked. method=', req.method);
    console.log('🔎 raw req.headers:', Object.keys(req.headers));

    // 🧩 Parse body if sent as raw JSON string
    if (typeof body === "string") {
      try {
        body = JSON.parse(body);
      } catch (err) {
        console.warn("⚠️ Invalid JSON body:", body);
        return res.status(400).send({ success: false, message: "Invalid JSON body" });
      }
    }

    // Support multiple body formats: parsed object, raw JSON string, or rawBody buffer
    let deviceId = (body.deviceId || body.device_id || "").trim();
    let uid = (body.uid || "").trim();

    // Fallback: try parsing rawBody if the parsed body did not contain fields
    if ((!deviceId || !uid) && req.rawBody && req.rawBody.length > 0) {
      try {
        const raw = req.rawBody.toString();
        console.log('🧾 rawBody present:', raw.length, 'bytes');
        const parsedRaw = JSON.parse(raw);
        deviceId = deviceId || (parsedRaw.deviceId || parsedRaw.device_id || "").trim();
        uid = uid || (parsedRaw.uid || "").trim();
      } catch (err) {
        // ignore JSON parse errors here; we'll handle missing fields below
        console.log('⚠️ rawBody parse failed:', err.message);
      }
    }

    console.log('📥 parsed body:', {
      deviceId: typeof body === 'string' ? '<string>' : body.deviceId,
      uid: typeof body === 'string' ? '<string>' : body.uid,
    });

    if (!deviceId || !uid) {
      console.warn('🚫 Missing deviceId or uid after parsing. body keys=', Object.keys(body || {}));
      // Log raw body for debugging (do not log sensitive tokens)
      try {
        if (req.rawBody && req.rawBody.length > 0) console.log('RAW_BODY:', req.rawBody.toString());
      } catch (e) {}
      return res.status(400).send({ success: false, message: "deviceId and uid required" });
    }

    const normalizedId = deviceId.toLowerCase();
    console.log('🔁 normalizedId =', normalizedId, 'uid =', uid);

    // 🔍 Get or create Firestore doc for the box
    const boxRef = db.collection("baryaBoxes").doc(normalizedId);
    const boxSnap = await boxRef.get();
    console.log('📦 boxSnap.exists =', boxSnap.exists);

    if (!boxSnap.exists) {
      try {
        await boxRef.set({
          deviceId: normalizedId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "unclaimed",
        });
        console.log(`✨ Auto-created new BaryaBox doc: ${normalizedId}`);
      } catch (err) {
        console.error('❌ Failed to auto-create BaryaBox doc:', err);
        return res.status(500).send({ success: false, message: 'Failed to create box doc' });
      }
    }

    const boxSnap2 = await boxRef.get();
    const boxData = boxSnap2.exists ? boxSnap2.data() || {} : {};
    console.log('📦 boxData =', boxData);

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
    console.log('🔗 checking RTDB path devices/' + trackerId);
    const trackerSnap = await trackerRef.once("value");
    console.log('🔗 trackerSnap.exists =', trackerSnap.exists());

    if (!trackerSnap.exists()) {
      console.warn('⚠️ RTDB tracker missing for', trackerId);
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
    console.log('✅ Firestore batch committed for uid=', uid, 'box=', normalizedId);

    // ✅ Update RTDB tracker binding
    await trackerRef.update({
      boundBoxId: normalizedId,
      driverUid: uid,
      boundAt: admin.database.ServerValue.TIMESTAMP,
    });
    console.log('✅ RTDB tracker updated for', trackerId);

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
