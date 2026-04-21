# 🛡️ VigilUPI – Behavioral Fraud Detection for UPI

![License](https://img.shields.io/badge/license-Academic%20%2F%20Hackathon-blue)
![Flutter](https://img.shields.io/badge/Flutter-Frontend-02569B?logo=flutter)

> **Note**: This is a prototype exploring behavioral biometrics and contextual risk for UPI security. It is not a production-grade fraud detection system.

---

## 🚨 The Problem

UPI fraud is rapidly increasing due to a variety of sophisticated attack vectors:
- **Social Engineering Attacks**
- **Screen Sharing Scams**
- **Remote Access Apps**
- **Impersonation** during transactions

**Current systems** typically rely on OTPs, static rules, and device-level checks. However, these mechanisms often fail once an attacker gains partial control of the device.

---

## 💡 Our Solution

**VigilUPI** is a multi-layer fraud detection prototype that validates transactions using an entirely different approach. Instead of merely trusting static credentials, the system continually evaluates: *"Does this interaction match the legitimate user?"*

We achieve this through:
- 🧑‍💻 **Behavioral Patterns (Soulprint)**
- 🌍 **Contextual Risk Signals**
- 📸 **Face Liveness Verification**

---

## 🧠 Core Components

### 1. Soulprint Engine (Behavioral Biometrics)
Monitors the device's **Accelerometer** and **Gyroscope**.
- **Mechanism:** Creates a behavior vector and compares it against a baseline profile.
- **Purpose:** Detect abnormal device handling patterns indicative of an unauthorized user or under-duress scenario.

### 2. Risk Context Service
Evaluates environmental anomalies.
- **📍 Location Changes**
- **📶 Network Conditions**
- **📞 Active Phone Call Status**
- **Purpose:** Outputs a risk score based on unusual contextual shifts.

### 3. Face Liveness Detection
Utilizes device camera + Google ML Kit.
- **Features:** Face detection and Blink verification.
- **Purpose:** Ensure a real, live user is present, thwarting spoofed media attacks.

### 4. UPI Transaction Layer (Simulation)
Analyzes transaction metadata.
- **Metrics:** Transaction amount, Receiver VPA patterns.
- **Purpose:** Flags potentially suspicious or anomalous transactions.

---

## 🔄 System Flow

1. **User initiates a UPI transaction**.
2. **System captures:**
   - Motion data
   - Context signals
3. **Behavioral pattern** is compared with the baseline.
4. **Risk score** is computed.
5. **Face liveness check** is performed.
6. **Decision:**
   - ✅ **Allow**
   - ⚠️ **Flag**
   - ❌ **Block**

---

## ⚙️ Tech Stack

- **Frontend:** Flutter
- **State Management:** Provider
- **Sensors:** `sensors_plus`
- **Face Detection:** Google ML Kit
- **Storage:** Hive
- **ML (Planned):** TensorFlow Lite

---

## 📂 Project Structure

```text
lib/
├── core/
│   └── soulprint_engine.dart
├── services/
│   ├── risk_context_service.dart
│   ├── face_liveness_service.dart
│   └── upi_gateway.dart
├── ui/
│   ├── biometric_visualizer.dart
│   └── transaction_screen.dart
└── main.dart

assets/
└── models/
    └── soulprint_model.tflite
```

---

## 🚧 Current Limitations

- Behavioral model is statistical, not fully ML-driven.
- Lacks advanced sensor noise filtering.
- Face liveness detection is basic.
- VPA fraud detection relies on static rules.
- Limited permission handling.
- No backend or real-time fraud intelligence integration.

---

## 🔮 Future Improvements

- [ ] Implement Mahalanobis distance / ML anomaly detection.
- [ ] Real-time camera stream for liveness.
- [ ] Adaptive behavioral learning.
- [ ] External fraud detection APIs.
- [ ] Improved signal processing.
- [ ] Backend-based intelligence system.

---

## ▶️ Setup & Run

### 1. Clone the repository
```bash
git clone <repo-url>
cd vigilupi
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Run the application
```bash
flutter run
```

> **Requirements:**
> - Android device or emulator
> - Camera and sensor permissions enabled

---

## 👨‍💻 Contributors

- **Vivek Kumar**
- **Team VigilUPI**
- **Priyanshu Kumar**
- **Mahatava Saxena**

---

## 📜 License

For academic / hackathon use only.
