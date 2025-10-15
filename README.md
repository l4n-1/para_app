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


