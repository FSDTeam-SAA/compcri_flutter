import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';

/// The publishable half of the RevenueCat key pair. It ships inside every copy
/// of the app by design and cannot move money on its own.
const _iosApiKey = 'appl_RkfBBmAqjfxWlZPtxLushjByazJ';

/// Set once the Play Store app has a key of its own. Until then Android shows
/// the screen without prices rather than opening a sheet that cannot complete.
const _androidApiKey = '';

/// The entitlement the API also checks; both sides must agree on the name.
const _premiumEntitlement = 'premium';

/// Raised when a purchase fails for a reason worth showing. Backing out of the
/// store sheet is not one of those — that returns false instead.
class PurchaseException implements Exception {
  PurchaseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Buying Premium through the App Store or Play Store.
///
/// Every call is safe on a build with no store key: [enable] records whether
/// the SDK came up and the rest return null or raise a readable message, so
/// tests and desktop builds still render the subscription screen.
class StorePurchases {
  StorePurchases._();

  static final StorePurchases instance = StorePurchases._();

  bool _available = false;
  String? _identified;

  bool get available => _available;

  static String get _apiKey {
    if (Platform.isIOS || Platform.isMacOS) return _iosApiKey;
    if (Platform.isAndroid) return _androidApiKey;
    return '';
  }

  /// Boots the SDK. False means this platform has no key yet.
  Future<bool> enable() async {
    if (_available) return true;
    if (_apiKey.isEmpty) return false;
    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Ties purchases to the account rather than to the device, using the id the
  /// API minted for this user. Without it a subscription bought on a phone
  /// would not unlock the same account elsewhere, and the webhook the store
  /// sends would name someone the backend does not recognise.
  Future<void> identify(String appUserId) async {
    if (!_available || appUserId.isEmpty || _identified == appUserId) return;
    try {
      await Purchases.logIn(appUserId);
      _identified = appUserId;
    } catch (_) {
      // Prices still load; the purchase itself re-checks identity.
    }
  }

  /// Drops the link on sign-out, so the next account on this phone does not
  /// inherit the previous one's entitlement.
  Future<void> forget() async {
    _identified = null;
    if (!_available) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  /// The packages on offer, or null when the store has nothing to show: no
  /// key, no network, or products not approved yet.
  Future<Offering?> offering() async {
    if (!_available) return null;
    try {
      return (await Purchases.getOfferings()).current;
    } catch (_) {
      return null;
    }
  }

  /// Runs the store's purchase sheet. True once the entitlement is live, false
  /// when the user backed out.
  Future<bool> buy(Package package) async {
    if (!_available) {
      throw PurchaseException('Purchases are not available on this build.');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _hasPremium(result.customerInfo);
    } catch (error) {
      if (_codeOf(error) == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      throw PurchaseException(_readable(error));
    }
  }

  /// Re-applies a subscription bought earlier or on another device. Apple
  /// requires this to be reachable without buying anything first.
  Future<bool> restore() async {
    if (!_available) {
      throw PurchaseException('Purchases are not available on this build.');
    }
    try {
      return _hasPremium(await Purchases.restorePurchases());
    } catch (error) {
      throw PurchaseException(_readable(error));
    }
  }

  static bool _hasPremium(CustomerInfo info) =>
      info.entitlements.active.containsKey(_premiumEntitlement);

  static PurchasesErrorCode? _codeOf(Object error) {
    try {
      return PurchasesErrorHelper.getErrorCode(error as dynamic);
    } catch (_) {
      return null;
    }
  }

  static String _readable(Object error) => switch (_codeOf(error)) {
    PurchasesErrorCode.purchaseNotAllowedError =>
      'This device is not allowed to make purchases.',
    PurchasesErrorCode.productAlreadyPurchasedError =>
      'You already own this subscription. Try Restore Purchases.',
    PurchasesErrorCode.networkError =>
      'The store could not be reached. Check your connection.',
    PurchasesErrorCode.paymentPendingError =>
      'The payment is still processing. Premium unlocks once it clears.',
    PurchasesErrorCode.receiptAlreadyInUseError =>
      'That purchase belongs to another account.',
    _ => 'The purchase could not be completed. Please try again.',
  };
}
