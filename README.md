# 📝 Changelog

## [COMMIT-10/15/2025-Leo]
### Added
- RoleRouter page to identify if the signed up account is a tsuperhero/pasahero.
- Qrscanpage that handles camera and Qr logic.
- Button redirects from signup_page and pasahero settings.
- tsuperhero_signup_page for tsupers.

### Fixed 
- Google Sign In.
- Pasahero and Tsuperhero homes.
- displayName on pasahero_home now shows first name.
- New GoogleMaps API key
- Scanning QR with already existing account while logged in now redirects to correct homepage.

### Known Issues
- Firebase pop up "Blocked due to unusual activity" when false, preventing added verification pop up and redirect to work.
- Tsuperhero_activation.dart.
- Google Sign in.
- Login page appears longer on real devices compared to emulator view — “Create Account” button partially off-screen.


## [COMMIT-10/13/2025-Leo]
### Added
- Home pages now separated but logic and controller/map handling is now in a separate dart (Home->shared_home(scaffold), pasahero_home(Widgets), tsuperhero_home(Widgets))

### Fixed 
- Google Sign In

### Known Issues
- Firebase pop up "Blocked due to unusual activity" when false, preventing added verification pop up and redirect to work.
- Tsuperhero_activation.dart.
- Google Sign in.
- Login page appears longer on real devices compared to emulator view — “Create Account” button partially off-screen.
- Google Maps not working on real device (probably devKey missing on my end).
- displayName displayed on Home page not updating, possibly Firebase auth cache.


## [COMMIT-10/13/2025-Leo]
### Added
- Email verification popup during sign-up. Checks for verification in real-time and directs User to pasahero_home after.
- Settings integration placeholder (Settings->settingspage(scaffold), PHsettings(Widgets), THsettings(Widgets))

### Fixed 
- Removed unnecessary lines of code from login.dart, signup_page2.dart
- Arranged directories to keep workspace clean.

### Known Issues
- Firebase pop up "Blocked due to unusual activity" when false, preventing added verification pop up and redirect to work.
- Tsuperhero_activation.dart.
- Google Sign in.
- Login page appears longer on real devices compared to emulator view — “Create Account” button partially off-screen.
- Google Maps not working on real device (probably devKey missing on my end).


## [COMMIT-11-18-25-ANTON]
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
