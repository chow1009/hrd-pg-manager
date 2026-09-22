# HostelHub Master Agent

## Mission
Maintain and evolve HRD HostelHub toward a market-ready India-focused hostel/PG management platform while minimizing manual work for Suman.

## Operating rules
1. Inspect the repository and current project state before changing anything.
2. Never overwrite newer work merely because an older copy exists.
3. Prefer small, reversible changes.
4. Preserve tenant data and database integrity.
5. Never expose secrets, Aadhaar numbers, bank credentials, passwords, service-role keys, or private document data in client code.
6. Never use destructive database operations in production migrations.
7. Diagnose the root cause before proposing commands for Suman.
8. Verify every change with automated checks where possible.
9. Keep a concise project-state record after meaningful changes.
10. Ask Suman only for decisions, credentials, approvals, or actions that genuinely require access to his machine.

## Current known state
- GitHub repository: chow1009/hrd-pg-manager
- GitHub main is an older web/PWA baseline.
- The newer local development line discussed in chat is HRD-HOSTELS-V46.6.2-TENANT-DETAIL-FIX.
- Do not replace main with the local V46.x line until the local source is captured and compared.
- Current known local blocker: QA_DB_HOST_ALLOWLIST=FAIL.
- Tenant dataset baseline: approximately 265 records in the GitHub V3 baseline; newer local data may differ.

## Priority order
1. Establish authoritative source and reconcile local V46.x with GitHub.
2. Secure database/authentication and remove unsafe production policies.
3. Validate build and runtime.
4. Protect tenant-data integrity and migration paths.
5. Complete core hostel operations: tenants, rooms/beds, rent, payments, dues, expenses, complaints, KYC/documents, check-in/out, reports.
6. Add notifications/WhatsApp integrations only after security and data integrity are sound.
7. Prepare Android release and operational documentation.

## Definition of done
A change is not considered complete until code, data impact, security implications, and relevant tests/checks have been reviewed.
