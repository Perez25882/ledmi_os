# Flutter Credit/Debit Card Data Extractor using Google ML-Kit

Flutter application designed to scan credit and debit cards using the device's camera. It leverages Google's ML Kit for on-device text recognition to automatically extract card numbers and expiry dates.

## 🎥 ScreenShot

https://github.com/user-attachments/assets/838a63f4-9b7e-4709-a68f-2481868735cb


## 🚀 Features

-   **Real-time Scanning**: Scans cards instantly using the device camera.
-   **Text Recognition**: Uses `google_mlkit_text_recognition` for accurate on-device OCR.
-   **Smart Extraction**: Automatically detects and extracts 13-16 digit card numbers and expiry dates.
-   **Haptic Feedback**: Provides vibration feedback upon successful detection.
-   **Privacy Focused**: All processing happens on the device; no image data is sent to external servers.

## 🛠 Plugins Used

This project relies on the following key Flutter plugins:

-   [camera](https://pub.dev/packages/camera): For accessing the device camera.
-   [google_mlkit_text_recognition](https://pub.dev/packages/google_mlkit_text_recognition): For optical character recognition (OCR).
-   [permission_handler](https://pub.dev/packages/permission_handler): For handling runtime permissions.
-   [vibration](https://pub.dev/packages/vibration): For haptic feedback.
-   [google_fonts](https://pub.dev/packages/google_fonts): For custom typography.

## ⚙️ Installation & Setup

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/Dinesh-Sowndar/flutter_ml_credit_card_data_extractor.git
    cd flutter_ml_credit_card_data_Extractor
    ```

2.  **Install dependencies:**

    ```bash
    flutter pub get
    ```

3.  **Platform Configuration:**

    ### iOS
    Add the following key to your `ios/Runner/Info.plist` file to allow camera access:
    
    ```xml
    <key>NSCameraUsageDescription</key>
    <string>This app needs camera access to scan credit cards.</string>
    ```

    ### Android
    Ensure your `android/app/build.gradle` defines a minimum SDK version compatible with ML Kit (usually 21 or higher).
    
    ```gradle
    minSdkVersion 21
    ```

4.  **Run the app:**

    ```bash
    flutter run
    ```

## 📱 Uses Cases

-   **E-commerce Apps**: Simplify the checkout process by allowing users to scan their cards instead of typing details manually.
-   **Fintech Applications**: Quickly onboard users by scanning their banking cards.
-   **Digital Wallets**: Easily add payment methods to a digital wallet.

## 🤝 Contributing

Contributions are welcome! If you find a bug or want to add a feature, please feel free to open an issue or submit a pull request.
