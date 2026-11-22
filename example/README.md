# Example

A single screen that takes one payment.

```bash
cd example
flutter create .   # scaffolds android/ and ios/ for your platform
flutter run
```

Two things to change before it can take a real payment:

1. **`createPayment`** in `lib/main.dart` calls your own server, which calls
   `POST /api/integration/init` and returns `checkout_url` and `invoice_id`. The stub in
   there throws until you point it at yours.
2. **The scheme.** `myapp` has to be declared in `android/app/src/main/AndroidManifest.xml`
   and `ios/Runner/Info.plist`, and set as the **Mobile App Return Scheme** on your GetPayIn
   integration. See [Setup](../doc/setup.md).
