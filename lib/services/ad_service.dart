// lib/services/ad_service.dart
import 'dart:async';

class AdService {
  // Demo ad units (Google test ads)
  static const String demoBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String demoInterstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const String demoRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  // Points system
  static const int pointsPerAd = 10;
  static const int pointsForDiscount = 100;
  static const double discountAmount = 10.0; // ₱10 discount

  // Commission rates
  static const double digitalPaymentCommission = 0.10; // 10%
  static const double cashCommission = 0.0; // 0% for cash payments

  // Simulate ad loading and showing
  static Future<bool> showDemoRewardedAd() async {
    // Simulate ad loading delay
    await Future.delayed(const Duration(seconds: 2));

    // In a real app, this would show actual ads
    // For demo, we'll simulate successful ad completion
    return true;
  }

  static Future<bool> showDemoInterstitialAd() async {
    // Simulate interstitial ad
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }

  // Calculate commission for digital payments
  static double calculateCommission(double fareAmount, bool isDigitalPayment) {
    if (isDigitalPayment) {
      return fareAmount * digitalPaymentCommission;
    }
    return cashCommission;
  }

  // Calculate driver earnings after commission
  static double calculateDriverEarnings(double fareAmount, bool isDigitalPayment) {
    final commission = calculateCommission(fareAmount, isDigitalPayment);
    return fareAmount - commission;
  }

  // Check if user has enough points for discount
  static bool canRedeemDiscount(int currentPoints) {
    return currentPoints >= pointsForDiscount;
  }

  // Apply discount to fare
  static double applyDiscount(double originalFare, int pointsToUse) {
    final discounts = (pointsToUse / pointsForDiscount).floor();
    return (originalFare - (discounts * discountAmount)).clamp(0, double.infinity);
  }

  // Calculate points needed for next discount
  static int pointsNeededForNextDiscount(int currentPoints) {
    return pointsForDiscount - (currentPoints % pointsForDiscount);
  }
}