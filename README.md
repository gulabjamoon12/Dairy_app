# 🐄 Dairy Farm Management App

A complete, feature-rich offline-first Flutter application designed to help dairy farmers and milk distributors efficiently manage their daily operations. Track daily milk collection, manage customer accounts, manage side-product inventory, generate automated bills, send native SMS alerts, and secure database backups directly to Google Drive.

---

## ✨ Key Features

### 👥 Customer Management

* **Onboard & Edit**: Seamlessly add new customers with custom phone numbers and delivery configurations.
* **Customer Ledger**: View individual dashboards highlighting historical analytics, total milk consumed, and active credit/debit logs.

### 🥛 Daily Dairy Entries

* **Shift Logging**: Support for independent morning (AM) and evening (PM) milk delivery logging.
* **Secondary Products**: Dedicated flows to manage production, tracking, and sales of secondary dairy goods like **Dahi (Curd)** and **Ghee**.
* **Retroactive Edits**: Robust calendar-based modification screen to adjust previous entries without disrupting accounting history.

### 💰 Billing & Finance

* **Dynamic Pricing Engine**: Set and modify base milk rates globally or tailor them to premium customer tiers.
* **Payment Architecture**: Track raw payments received against pending monthly statements.
* **Tabbed Report Controls**: Dynamic UI filters containing multi-metric grids for billing statements, overall farm stats, ledger balances, and data exporting.

### 🚀 Smart Native Services

* **SMS Integration**: Automated dispatch systems running over local device telephony packages to notify users immediately on daily logs or bill calculations.
* **Google Drive Backup & Restore**: Secure cloud replication routines that backup local SQLite files via standard Google OAuth flows.
* **File Exporting**: Render reports instantly into portable document and table formats.


---

## 🛠️ Architecture & Tech Stack

* **UI Framework**: Flutter (Dart)
* **Local Database**: SQLite (`sqflite` with raw embedded queries)
* **Fonts**: Space Grotesk (Headers) & Inter (Body text)
* **Cloud Infrastructure**: Google Drive API & Google Sign-In SDK
* **Hardware Integration**: Native Telephony SMS Services

---

## 📂 Codebase Organization

A mapping of the key source architecture inside the core package directory:

```text
lib/
│
├── screens/                 # User Interface Screens
│   ├── report/              # Multi-Tab reporting (Billing, Stats, Payments, Export)
│   ├── daily_milk_entry...  # Shift log view controller
│   └── ...
│
├── services/                # Device Hardware Drivers & External APIs
│   ├── backup_service.dart  # Native file management for database structures
│   ├── database_helper.dart # SQLite schema and transactional query engines
│   ├── export_service.dart  # Data serialization (CSV/PDF)
│   ├── google_drive_service # Google Cloud Drive file pipelines
│   └── sms_service.dart     # Direct Telephony platform channel wrappers
│
├── widgets/                 # Atomic custom components (Cards, Buttons)
├── theme/                   # Theme settings with unified styling rules
└── utils/                   # Debouncers, custom date parsers, formatters

```

---

## 🚀 Installation & Setup

Get your local environment ready for testing or feature enhancement using the following checklist.

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (Latest stable release)
* Android Studio, VS Code, or Xcode
* Active physical mobile device or configured system emulator

### Running Locally

1. **Clone the code repository:**
```bash
git clone https://github.com/gulabjamoon12/dairy_app.git
cd dairy_app

```


2. **Retrieve project pub packages:**
```bash
flutter pub get

```


3. **Configure Google Cloud Identity Console (For Cloud Sync Features):**
* Download your custom `google-services.json` setup file.
* Place the file directly inside the `android/app/` subdirectory directory.
* Ensure your OAuth app configuration on the GCP console includes access scopes for Google Drive AppData (`.../auth/drive.appdata`).


4. **Launch Application:**
```bash
flutter run

```



### 🔒 Required Application Permissions

To ensure smooth runtime operations, make sure the app has permissions enabled for:

* **Storage Read/Write**: Handles caching and document generations.
* **Native SMS Send**: Used by the platform channels to trigger customer billing texts.

---

##Contact

* **Developer:** Nikhil
* **Email:** [snbbnf4tz@mozmail.com]()

---

## 🤝 Open Source Contribution

Code improvements, feature additions, or issue reports are highly appreciated.

1. Fork the codebase repository.
2. Branch out into your working environment (`git checkout -b feature/YourFeatureName`).
3. Commit cleanly labeled changes (`git commit -m 'Implement YourFeatureName'`).
4. Push code up to your fork (`git push origin feature/YourFeatureName`).
5. Open a formal Pull Request against the main branch.


## 💖 Support

Give a ⭐️ if this project helped you scale your agricultural workflow or dairy distribution application!
