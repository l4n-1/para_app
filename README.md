# 📝 Changelog

## [COMMIT-10/15/2025-Bonus]
### Added
- Location permission and error handling in shared_home.dart to prevent white screen when GPS is off or unavailable.
- Profile Settings page (profile_settings.dart) where Pasahero and Tsuperhero users can update username, contact number, and date of birth.
- “Profile Settings” button added in side panel for both user roles.
- QR validation logic via Firebase Realtime Database to ensure scanned QR codes are valid and not reused.
- Updated plate_number_input.dart to mark device IDs as assigned after activation.

### Fixed
- Updated auth_service.dart for compatibility with google_sign_in: ^7.1.1.
  - Replaced deprecated signIn() and signInSilently() with authenticate().
  - Removed accessToken and added initialize() / disconnect() methods.
- Cleaned deprecated warnings (withOpacity, unused vars) and async gap issues in shared_home.dart.
- Improved role-based display names in SharedHome (Pasahero = firstName, Tsuperhero = plateNumber).

### Known Issues
- Google users without complete profile info (username/contact/DOB) still need automatic redirect to Profile Setup.
- Firebase pop-up “Blocked due to unusual activity” may still occur during verification.
- Google Maps API may fail on real devices if SHA key is missing.
- Tsuperhero “Go Online” button not yet connected to backend route system.


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

### Known Issues
- Firebase pop up "Blocked due to unusual activity" when false, preventing added verification pop up and redirect to work.
- Tsuperhero_activation.dart.
- Google Sign in.
- Login page appears longer on real devices compared to emulator view — “Create Account” button partially off-screen.
- Google Maps not working on real device (probably devKey missing on my end).


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
- Email verification pop-up during sign-up. Checks for verification in real-time and directs User to pasahero_home after.
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

## [COMMIT-10/13/2025-Bonus]
✅ Added
- Implemented Tsuperhero Activation Flow (tsuperhero_activation.dart)
  → QR scanning now routes user based on login state:
  - Logged-in users → PlateNumberInputPage
  - New users → SignupTsuperhero
- Enhanced SignupStep2 (Pasahero registration)
  → Added contact number (PH format: 09XXXXXXXXX)
  → Added password validation (min 8 chars, 1 uppercase, 1 number)
  → Retained email verification popup + real-time verification redirect
- Updated LoginPage
  → Supports login using either email OR username
  → Redirects automatically based on user role (pasahero/tsuperhero)

🛠️ Fixed
- Confirmed the added email verification pop-up during sign-up working. Improvised a bypass code for the firebase to not
  actually send an email verification to prevent pop-ups of "Blocked due to unusual activity" but reverted things back to
  normal before pushing.
- Resolved null-safety issues in QR scanning flow
- Adjusted pasahero_home.dart layout to fix map overflow
- Patched deprecated 'desiredAccuracy' calls
- Verified email verification and redirect flow
- Confirmed auto-login redirect works for verified users

🚧 In Progress
- SignupTsuperhero page (plate + contact + password)
- Jeepney marker rotation + Firestore tracking
- Google Maps API verification on real devices
- Settings page styling (Leo)

⚠️ Known Issues
- Firebase “Blocked due to unusual activity” (temporary bypass)
- Google Maps may fail on real device without proper API key
- Minor login UI clipping on small screens