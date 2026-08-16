# Udhaar/Ledger Management App

## What's included

- `backend/` — Node.js + Express + SQLite API (tested, working)
  - Login (Owner default: `owner` / `owner123` — **change this immediately**)
  - Customers CRUD (Owner-only add/edit/delete, Worker can view)
  - Transactions (Owner-only add/delete, balance auto-updates)
  - Google Sheets sync (`/api/sheets-sync/preview` and `/confirm`) — Owner-only
- `frontend/` — Flutter app skeleton
  - Login screen
  - Owner dashboard (customer list + balances + "Sync from Google Sheet" button with preview/confirm)
  - Worker dashboard (view-only customer list + balances)
  - `ApiService` centralizing all backend calls

## What you still need to do (in order)

### 1. Get a PC that stays on 24/7
Doesn't have to be your shop PC yet — any always-on PC/laptop with internet works to start. When your shop PC is ready, just move the `backend/` folder there.

### 2. Run the backend
```
cd backend
npm install
cp .env.example .env    # then edit .env with real values
npm start
```

### 3. Google Sheets connection
1. Go to Google Cloud Console → create a project → enable **Google Sheets API**
2. Create a **Service Account** → generate a JSON key → save it as `backend/config/service-account-key.json`
3. Open your existing Google Sheet → **Share** it with the service account's email (found inside the JSON key) → give **Editor** access
4. Copy your Sheet ID (from its URL) into `.env` as `GOOGLE_SHEET_ID`
5. Make sure your Sheet's columns match: `Name | HouseNumber | Type (udhaar/wasooli) | Amount | Note | Synced`

### 4. Expose backend to the internet (Cloudflare Tunnel)
So the app works from anywhere, not just shop Wi-Fi. I'll walk you through this as the next step — just say "next step" when ready.

### 5. Run the Flutter app
Requires Flutter SDK installed on your development machine (not this sandbox):
```
cd frontend
flutter pub get
flutter run
```
Update `baseUrl` in `lib/services/api_service.dart` to your Cloudflare Tunnel URL once you have it.

### 6. Create worker logins
Once logged in as Owner, use `POST /api/auth/create-worker` (or we'll add a screen for this) to create worker accounts — they'll only ever see the view-only dashboard.
