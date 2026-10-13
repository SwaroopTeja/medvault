# MedVault: Product & Technical Specification

> Working name: **MedVault** (change freely).
> Status: Draft v0.1
> Rule for AI agents and contributors: **read this file before every task. If a requested change conflicts with the Non-Negotiable Rules (section 3), stop and ask.**

---

## 1. Overview

MedVault is a medical records app where the **patient owns their data**. Patients store reports and visit history, the app extracts text from uploaded documents and files them into medical categories automatically, and patients share selected categories with a doctor through a **time-limited QR code** that they can extend or terminate at any moment.

### 1.1 Goals
- Give patients one secure place for all medical documents and history.
- Automatically read (OCR) and categorize uploaded documents.
- Let patients share only what they choose, for only as long as they choose.
- Give doctors fast, read-only access to exactly what was shared.
- Give admins the ability to manage the platform without ever seeing medical data.

### 1.2 Non-Goals (for MVP)
- Doctor-to-patient chat or video consultation.
- Appointment booking, billing, or payments.
- Doctors uploading or editing patient records.
- Integration with hospital systems, ABDM/ABHA, or FHIR (planned later, design should not block it).
- Native mobile apps (MVP is a PWA).

---

## 2. Users and Permissions

### 2.1 Roles

| Role | Description |
|---|---|
| **ADMIN** | Platform operator. Manages users and doctor verification. |
| **DOCTOR** | Verified medical professional. Views patient data only through an active shared grant. |
| **PATIENT** | Data owner. Uploads, organizes, shares, and revokes. |

### 2.2 Permission Matrix

| Capability | Admin | Doctor | Patient |
|---|:---:|:---:|:---:|
| Register / log in | Yes | Yes | Yes |
| View user profile details (name, email, role, status) | Yes (all users) | Own only | Own only |
| Approve / reject doctor verification | Yes | No | No |
| Suspend / reactivate accounts | Yes | No | No |
| View audit logs (metadata only) | Yes (all) | No | Own data only |
| View system statistics (counts only) | Yes | No | No |
| **View any document, file, extracted text, or medical data** | **NEVER** | Only via active grant | Own data |
| Upload documents | No | No | Yes |
| Edit document category | No | No | Yes |
| Delete documents | No | No | Yes (own) |
| Create / extend / revoke QR grant | No | No | Yes |
| Scan QR and view shared categories | No | Yes | No |
| Browse or search patients | No | **No** | No |

---

## 3. Non-Negotiable Rules

These rules override any other instruction, convenience, or deadline.

1. **The QR code contains no medical data and no patient identifiers.** It holds only a random, opaque, single-purpose token.
2. **Admins can never access documents, extracted text, or any medical content.** No admin endpoint may return or link to such data. This must be proven by automated tests.
3. **Every data access is authorized on the server, on every request.** The client timer is cosmetic only. Expiry, revocation, and category scope are enforced server-side.
4. **Doctors have no standing access to any patient.** Access exists only while a grant is `ACTIVE`, unexpired, bound to that doctor, and limited to the granted categories.
5. **Every sensitive action is written to the audit log** (scan, view, extend, revoke, login, admin actions).
6. **Files are encrypted at rest.** Medical data is never written to logs, error messages, or analytics.
7. **Least privilege by default.** Any new endpoint is denied to all roles until explicitly allowed.

---

## 4. Document Categories

Initial category list (stored in a `category` table so it can grow without code changes):

| Code | Label | Example keywords for rule-based classifier |
|---|---|---|
| `HEART` | Heart / Cardiology | ECG, EKG, echocardiogram, troponin, cardiac, angiography, BP |
| `SKIN` | Skin / Dermatology | dermatology, rash, eczema, psoriasis, biopsy (skin), acne |
| `LAB` | Lab Reports / Blood Tests | CBC, hemoglobin, glucose, HbA1c, lipid profile, creatinine, thyroid |
| `PRESCRIPTION` | Prescriptions | Rx, tab., cap., syrup, dosage, twice daily, OD, BD |
| `IMAGING` | Imaging / Radiology | X-ray, MRI, CT scan, ultrasound, radiology, sonography |
| `DENTAL` | Dental | dental, tooth, extraction, root canal, orthodontic |
| `EYE` | Eye / Ophthalmology | ophthalmology, vision, retina, cataract, intraocular |
| `ORTHO` | Bones & Joints | fracture, orthopedic, ligament, arthritis |
| `VACCINATION` | Vaccination | vaccine, immunization, dose, booster |
| `DISCHARGE` | Discharge Summaries | discharge summary, admission, hospital stay |
| `OTHER` | Uncategorized | Fallback when confidence is low |

A document can belong to **one primary category** (MVP). Multi-category tagging is a later enhancement.

---

## 5. Functional Requirements

### 5.1 Authentication and Accounts

- **FR-A1** Users register with email and password. Role is chosen at sign-up for PATIENT or DOCTOR. ADMIN accounts are created only by seeding or by an existing admin.
- **FR-A2** Doctor accounts are created in `PENDING_VERIFICATION` state. They must submit a medical registration number and (optionally) a license document. They cannot scan QR codes until an admin sets the status to `ACTIVE`.
- **FR-A3** Login returns a short-lived JWT access token and a rotating refresh token.
- **FR-A4** Passwords are hashed with BCrypt or Argon2. Minimum password policy enforced.
- **FR-A5** MFA (TOTP) is required for DOCTOR and ADMIN, optional for PATIENT (post-MVP for patients).
- **FR-A6** Admin can suspend an account. Suspended users cannot log in, and all their active grants are revoked immediately.

### 5.2 Patient: Document Management

- **FR-P1** Patient uploads documents (PDF, JPG, PNG; max 10 MB each; configurable). Camera capture on mobile is supported.
- **FR-P2** Server validates file type by content (magic bytes), not just extension, and scans for size and basic safety.
- **FR-P3** Upon upload, the document is encrypted and stored. Status becomes `PROCESSING`.
- **FR-P4** An asynchronous OCR job extracts text. A classifier assigns a category with a confidence score. Status becomes `READY`.
- **FR-P5** If confidence is below the threshold, the category is `OTHER` and the patient is prompted to confirm or choose a category.
- **FR-P6** Patient can manually change a document's category at any time.
- **FR-P7** Patient can set metadata: title, visit date, doctor name, hospital (all optional; OCR may suggest values).
- **FR-P8** Patient views documents by category, by visit date (timeline), and via search over extracted text.
- **FR-P9** Patient can delete a document. Deletion removes the file, extracted text, and metadata, and the document disappears from any active grant.
- **FR-P10** Patient has a basic profile: name, date of birth, blood group, allergies, chronic conditions, emergency contact.

### 5.3 Patient: QR Sharing

- **FR-S1** Patient creates a share by selecting one or more categories (or specific documents, post-MVP) and a duration (presets such as 15 min, 30 min, 1 hr, 24 hr, plus custom; maximum 7 days).
- **FR-S2** Server creates an `AccessGrant` with status `PENDING` and generates a QR token. The QR is displayed in the app and the countdown starts **when the doctor claims it** (see 6.2). A configurable QR claim window (default 5 minutes) applies; an unclaimed QR expires.
- **FR-S3** Patient sees a live view of active shares: categories, remaining time, doctor name (once claimed), and status.
- **FR-S4** Patient can **extend** an active grant (add time, subject to the 7-day total cap).
- **FR-S5** Patient can **terminate** (revoke) a grant at any time. Revocation takes effect immediately, including on the doctor's open screen.
- **FR-S6** Patient receives a notification when the QR is scanned, 5 minutes before expiry, and on expiry or revocation.
- **FR-S7** Patient can view the access history: which doctor, which categories, when, and which documents were opened.
- **FR-S8** (Optional) **Emergency card**: a separate QR exposing only blood group, allergies, chronic conditions, and emergency contacts, with no login required to view. Disabled by default and enabled by the patient.

### 5.4 Doctor

- **FR-D1** Doctor opens the in-app scanner and scans the patient's QR.
- **FR-D2** Server validates and claims the token (see 6.2). On success, the doctor sees the patient's name and the shared categories only.
- **FR-D3** Doctor views documents in a **read-only viewer** showing the extracted text and the original file. A visible countdown shows the remaining access time.
- **FR-D4** Downloading is disabled in the UI. (Note: true prevention of copying is not technically possible. Controls are deterrents plus audit logging.)
- **FR-D5** When a grant expires or is revoked, the doctor's screen locks immediately and API calls return `403`.
- **FR-D6** Doctor sees a list of their recent sessions (patient name, categories, time) but **cannot reopen expired ones**.

### 5.5 Admin

- **FR-M1** Admin dashboard shows counts only: total users by role, pending doctor verifications, active grants, uploads per day. No content.
- **FR-M2** Admin lists and searches users and views **profile details** (name, email, role, status, created date, doctor registration number). Admin **does not** see patient documents, extracted text, categories of a patient's documents, or patient medical profile fields (blood group, allergies, conditions).
- **FR-M3** Admin reviews doctor verification requests and approves or rejects with a reason.
- **FR-M4** Admin suspends or reactivates accounts.
- **FR-M5** Admin views the audit log (action, actor, target ID, timestamp, IP). Log entries never contain medical content.
- **FR-M6** Admin manages the category list (add/rename/disable categories).

---

## 6. Core Flows

### 6.1 Patient uploads a document
1. Patient selects or captures a file.
2. Client uploads via `POST /api/documents`.
3. Server validates, encrypts, stores the file, and creates a `Document` with status `PROCESSING`.
4. Async OCR job extracts text and runs the classifier.
5. Server updates the document with text, category, and confidence, and status `READY`.
6. Client is notified (polling or SSE). Patient reviews and optionally corrects the category.

### 6.2 QR sharing lifecycle (core feature)

```
PENDING --(doctor claims)--> ACTIVE --(time runs out)--> EXPIRED
   |                           |
   |                           +--(patient revokes)--> REVOKED
   +--(claim window passes)--> EXPIRED
```

1. **Create:** patient picks categories and duration. Server creates an `AccessGrant` (`PENDING`) with a random token (at least 128 bits of entropy). Only a **hash** of the token is stored.
2. **Display:** the QR encodes the token (or a short URL containing it). Nothing else.
3. **Claim:** doctor (authenticated, role `DOCTOR`, status `ACTIVE`) scans and calls `POST /api/shares/claim` with the token.
   - Token valid, `PENDING`, and not past the claim window? Bind the grant to this doctor, set `ACTIVE`, set `activated_at = now`, `expires_at = now + duration`.
   - Otherwise reject. **A token can be claimed exactly once.** A second scan, even by the same doctor, fails.
4. **Access:** every document request by the doctor passes through one central authorization check:
   - grant exists and is bound to this doctor
   - status is `ACTIVE`
   - `now < expires_at`
   - document's category is in the granted categories
   - document belongs to the grant's patient
   - Any failure returns `403` and is audit-logged.
5. **Live updates:** server pushes `EXTENDED`, `REVOKED`, and `EXPIRED` events (SSE or WebSocket) to both parties.
6. **Extend:** patient calls `POST /api/shares/{id}/extend` with extra minutes. Only `ACTIVE` grants can be extended. Total lifetime cannot exceed the cap.
7. **Revoke:** patient calls `POST /api/shares/{id}/revoke`. Status becomes `REVOKED` immediately.
8. **Expiry:** enforced by the `expires_at` check on every request, and additionally by a scheduled job that flips status to `EXPIRED` and emits the event.

### 6.3 Doctor verification
1. Doctor registers and submits registration details. Status: `PENDING_VERIFICATION`.
2. Admin reviews and approves or rejects.
3. On approval, the doctor can log in with full doctor capabilities. On rejection, the reason is shown.

---

## 7. OCR and Classification

### 7.1 Pipeline
1. Pre-process images (deskew, grayscale, contrast) to improve accuracy.
2. For PDFs: extract embedded text first; if none, rasterize pages and run OCR.
3. Run OCR (initial engine: **Tesseract via Tess4J**; keep behind an interface so the engine can be swapped for PaddleOCR or a cloud service).
4. Classify extracted text.
5. Store `extracted_text`, `category`, `confidence`, `classified_by` (`RULES`, `ML`, `USER`).

### 7.2 Classification strategy
- **Layer 1 (MVP):** keyword and rule scoring against the category table. The highest-scoring category above the threshold wins.
- **Layer 2 (later):** ML or LLM-based classifier for ambiguous documents.
- Confidence below threshold (default 0.6) gives `OTHER` plus a prompt for the patient to confirm.
- User corrections are stored and can later improve the rules or model.

### 7.3 Known limitations
- Handwritten prescriptions will often be read poorly. The UI must make manual correction easy and never imply perfect accuracy.
- If a cloud OCR service is ever used, it requires explicit patient consent and a data processing review, since medical data would leave the system.

---

## 8. Data Model (high level)

Detailed schema lives in `docs/data-model.md`. Core entities:

| Entity | Key fields |
|---|---|
| `User` | id, email, password_hash, role, status, mfa_enabled, created_at |
| `PatientProfile` | user_id, full_name, dob, gender, blood_group, allergies, conditions, emergency_contact |
| `DoctorProfile` | user_id, full_name, registration_number, specialization, verification_status, verified_by, verified_at |
| `Category` | id, code, label, keywords, active |
| `Document` | id, patient_id, category_id, title, visit_date, storage_key, encryption_key_ref, mime_type, size, extracted_text, confidence, classified_by, status, created_at |
| `AccessGrant` | id, patient_id, doctor_id (nullable until claimed), token_hash, status, duration_minutes, claim_expires_at, activated_at, expires_at, revoked_at, total_extended_minutes |
| `AccessGrantCategory` | grant_id, category_id |
| `AuditLog` | id, actor_id, actor_role, action, target_type, target_id, ip, user_agent, timestamp, metadata (no medical content) |
| `Notification` | id, user_id, type, payload, read, created_at |

Rules:
- `extracted_text` is only ever returned through patient endpoints or through a grant-checked doctor endpoint.
- The admin module's repositories and DTOs must not reference `Document`, `extracted_text`, or `PatientProfile` medical fields.

---

## 9. API Overview

Full OpenAPI contract lives in `docs/openapi.yaml`. Base path: `/api`.

| Module | Endpoints (summary) | Roles |
|---|---|---|
| Auth | `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout`, `/auth/mfa/*` | Public / authenticated |
| Patient profile | `GET/PUT /patient/profile` | PATIENT |
| Documents | `POST /documents`, `GET /documents`, `GET /documents/{id}`, `PATCH /documents/{id}` (category, metadata), `DELETE /documents/{id}` | PATIENT |
| Categories | `GET /categories` | Authenticated |
| Shares (patient) | `POST /shares`, `GET /shares`, `POST /shares/{id}/extend`, `POST /shares/{id}/revoke`, `GET /shares/{id}/access-history` | PATIENT |
| Shares (doctor) | `POST /shares/claim`, `GET /doctor/sessions`, `GET /doctor/sessions/{grantId}/documents`, `GET /doctor/sessions/{grantId}/documents/{docId}` | DOCTOR |
| Live events | `GET /shares/{id}/events` (SSE) | PATIENT, DOCTOR (bound) |
| Admin | `GET /admin/users`, `GET /admin/users/{id}`, `PATCH /admin/users/{id}/status`, `GET /admin/doctors/pending`, `POST /admin/doctors/{id}/verify`, `GET /admin/audit-logs`, `GET /admin/stats`, `*/admin/categories` | ADMIN |
| Notifications | `GET /notifications`, `PATCH /notifications/{id}/read` | Authenticated |

---

## 10. Security Requirements

- **Transport:** HTTPS only. HSTS enabled.
- **Authentication:** JWT access tokens (15 min), rotating refresh tokens, revocation on logout and suspension.
- **Authorization:** role-based method security plus an explicit grant check service for doctor access. Deny by default.
- **Encryption at rest:** files encrypted with AES-256-GCM before storage. Keys are managed through a key management abstraction (local key file for dev, cloud KMS or Vault for production). Database disk encryption enabled in production.
- **QR tokens:** at least 128-bit random, stored hashed, single-claim, expiring, and bound to a doctor on claim.
- **Rate limiting:** login, token claim, and upload endpoints. Lock out repeated invalid token claims.
- **Input validation:** content-type sniffing, size limits, filename sanitization, no path traversal. Files are never served from a public bucket. All access goes through the API with short-lived streaming.
- **Logging:** structured logs with no PII or medical content. Audit logs are append-only.
- **Secrets:** never committed to Git. Use environment variables or a secrets manager.
- **Headers and CORS:** strict CORS allowlist, security headers set, CSRF strategy documented for cookie use.
- **Dependencies:** automated vulnerability scanning in CI.
- **Admin separation:** admin module has its own DTOs and repositories that physically cannot map medical content.

### 10.1 Compliance awareness (India)
- **DPDP Act 2023:** explicit consent, purpose limitation, right to access, correction, and erasure, breach notification process.
- Provide a "delete my account and all data" function for patients.
- Maintain a privacy policy and consent screens at registration and before first upload.
- Plan for ABDM/ABHA and FHIR compatibility in a later phase. Keep the data model mappable.

---

## 11. Non-Functional Requirements

- **Performance:** document list loads under 1 s; OCR completes within 30 s for a typical single-page document; QR claim responds under 500 ms.
- **Availability:** target 99.5% for MVP.
- **Scalability:** stateless API instances; files in object storage; Redis for ephemeral state.
- **Accessibility:** WCAG 2.1 AA for core screens.
- **Usability:** mobile-first, usable one-handed, large tap targets, clear countdown display.
- **Observability:** health checks, metrics, and error tracking (without PII).
- **Backups:** daily database backups and versioned object storage, with restore tested.

---

## 12. Technology Stack

| Layer | Choice |
|---|---|
| Backend | Java 21, Spring Boot 3.x |
| Security | Spring Security, JWT |
| Persistence | Spring Data JPA, PostgreSQL, Flyway migrations |
| Cache / TTL | Redis |
| File storage | MinIO (dev) / S3-compatible (prod) |
| OCR | Tess4J (Tesseract), behind an `OcrEngine` interface |
| QR generation | ZXing |
| Async | Spring `@Async` / task executor (queue later if needed) |
| Live updates | Server-Sent Events (SSE) |
| API docs | springdoc-openapi |
| Testing | JUnit 5, Mockito, Testcontainers |
| Frontend | React (Vite) + TypeScript + Tailwind CSS + shadcn/ui, as a PWA |
| QR scanning | Browser camera API (e.g. `html5-qrcode` or `@zxing/browser`) |
| Dev environment | Docker Compose (Postgres, Redis, MinIO) |
| CI/CD | GitHub Actions |

### 12.1 Backend package structure
```
com.medvault
 ├── auth        (JWT, login, MFA, roles)
 ├── user        (patient, doctor, admin profiles)
 ├── document    (upload, storage, encryption)
 ├── ocr         (extraction, classification)
 ├── sharing     (grants, QR, extend, revoke, events)
 ├── audit       (audit logging)
 ├── admin       (metadata-only management)
 ├── notification
 └── common      (exceptions, config, utils)
```

---

## 13. MVP Scope and Milestones

**MVP = Phases 1 to 3.** Do not start later items until the MVP works end to end.

| Phase | Scope | Done when |
|---|---|---|
| 1. Foundation | Project setup, Docker Compose, auth, roles, user entities, admin basics (list users, verify doctors, suspend) | All three roles can log in; admin can approve a doctor; role tests pass |
| 2. Documents and OCR | Upload, encrypted storage, async OCR, rule-based classification, manual override, patient document UI | Patient uploads a report and sees it filed in the right category |
| 3. QR sharing | Grants, QR generation, single claim, enforced expiry, extend, revoke, live countdown, audit log | Full flow works; replay, expired, revoked, and wrong-doctor tests all fail correctly |
| 4. Doctor and admin UX | Scanner, read-only viewer, admin dashboard and audit viewer | Doctor and admin screens polished |
| 5. Hardening | MFA, rate limits, security test suite, penetration-style tests, compliance review | No open high-severity findings |
| 6. Launch | UI polish, E2E tests, CI/CD, deployment, pilot | Pilot users onboarded |

---

## 14. Acceptance Tests (must pass before MVP is considered done)

**Access control**
- [ ] Admin calling any document or extracted-text endpoint receives `403`.
- [ ] Admin user-detail responses contain no medical fields.
- [ ] Doctor with no grant cannot fetch any patient data.
- [ ] Doctor cannot access a category that was not included in the grant.
- [ ] Doctor B cannot use a grant claimed by Doctor A.
- [ ] Patient cannot access another patient's documents.

**QR lifecycle**
- [ ] QR token cannot be claimed twice.
- [ ] Unclaimed QR expires after the claim window.
- [ ] After `expires_at`, all doctor requests return `403`, even if the client timer is tampered with.
- [ ] Revoke takes effect on the very next request and pushes a live event to the doctor's screen.
- [ ] Extend increases `expires_at` and respects the maximum cap.
- [ ] Deleting a document removes it from active grants immediately.
- [ ] Suspending a doctor or patient revokes their active grants.

**Documents and OCR**
- [ ] Disallowed file types and oversized files are rejected.
- [ ] A sample ECG report is classified as `HEART`; a sample CBC report as `LAB`.
- [ ] Low-confidence documents land in `OTHER` and prompt the patient.
- [ ] Stored files are unreadable without the application's decryption key.

**Audit**
- [ ] Every scan, view, extend, revoke, and admin action creates an audit entry with no medical content.

---

## 15. Open Questions

Decide these before or during Phase 1 and record the answer here.

1. Should a patient be able to share **specific documents** in addition to whole categories? (Proposed: post-MVP.)
2. Should the shared-access timer start at **QR creation** or at **doctor scan**? (Proposed in this spec: at scan, with a short claim window.)
3. Should patients be able to pre-approve a **trusted doctor** for repeat access without a new QR? (Proposed: post-MVP.)
4. Maximum single grant duration and total cap? (Proposed: 7 days.)
5. Will the doctor verification use manual admin review only, or an external medical council registry check later?
6. Cloud OCR allowed with consent, or strictly on-premises? (Proposed: on-premises for MVP.)
7. Hosting region and provider? (Medical data residency in India recommended.)

---

## 16. Instructions for AI Coding Agents

- Read this file and `docs/data-model.md` before every task.
- Work on **one module or feature at a time**. Produce a plan first and wait for approval before large changes.
- Write tests alongside every feature, especially for authorization and the QR lifecycle.
- Never log, print, or return medical content outside the paths allowed in this spec.
- Never add an endpoint without stating which roles may call it.
- Do not change the Non-Negotiable Rules. If a task seems to require it, stop and ask.
- Do not design or restyle the frontend. Frontend work is limited to API client code, state, and wiring into the provided design components.
- Keep security-critical code (grant validation, encryption, token handling) small, isolated, and heavily tested so it can be reviewed by a human.
