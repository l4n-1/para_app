ANTON COMMIT

CHANGES MADE:
1. Fixed Giant Red Pin Issue
   The giant red pin is coming from the updateUserLocation() method

Added _removeUserMarker() method to clear it

The pin is created when updateUserLocation() is called

2. Updated Coin Dialog Options
   First button: Changed to "Buy Coins using Online Currency" (green color)

Second button: Changed to "Watch Ads to Get Coins" (amber color)

3. Added Current Coins Display
   Added "Para! Coins: 0.00" display in a blue background box

The coins are loaded from Firestore (you'll need to add a 'coins' field to your users collection)

4. Added New Method
   _showBuyCoinsScreen() - for the online currency purchase