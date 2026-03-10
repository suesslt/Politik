# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Politik is a Swiss Federal Parliament data analysis app with two components:
- **iOS/macOS SwiftUI app** (`/Politik`) — SwiftData persistence, syncs from parlament.ch OData API, Claude AI-powered political analysis
- **Vapor backend server** (`/PolitikServer`) — PostgreSQL via Fluent ORM, Leaf templates, REST API + web UI

## Build & Run

### iOS/macOS App
```bash
# Build from command line
xcodebuild -project Politik.xcodeproj -scheme Politik build

# Run tests
xcodebuild -project Politik.xcodeproj -scheme Politik test
```
Open `Politik.xcodeproj` in Xcode for normal development.

### Vapor Server
```bash
cd PolitikServer

# Start PostgreSQL
docker compose up -d

# Build & run server
swift build
swift run App serve

# Run server tests
swift test
```

**Required environment variables for server:** `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `CLAUDE_API_KEY`

## Architecture

### iOS/macOS App (SwiftUI + SwiftData)
- **Models/** — SwiftData `@Model` classes: Session, Geschaeft, Parlamentarier, Wortmeldung, Abstimmung, Stimmabgabe, Proposition, PersonInterest, PersonOccupation, DailyReport
- **Views/** — SwiftUI views, tab-based navigation (5 tabs)
- **Services/** — `@MainActor @Observable` service classes:
  - `ParlamentService` — Fetches from `ws.parlament.ch/odata.svc`, supports incremental sync via Modified timestamp
  - `ClaudeService` — AI analysis with tool-calling for political positioning on 7 axes and proposition extraction
  - `SessionSyncService` — Orchestrates session data sync
  - `DailyReportService` — Generates daily parliament summaries
  - `DataExportImportService` — JSON export/import (v3 format)

### Vapor Server (MVC + Services)
- **Controllers/** — 10 controllers for web routes (session-auth, Leaf templates) and REST API (`/api/v1/`, basic auth)
- **Models/** — Fluent ORM models mirroring the SwiftData models
- **Migrations/** — Database schema migrations
- **Middleware/** — `EnsureAuthenticatedMiddleware`, `EnsureAdminMiddleware`
- **Services/** — `ParlamentService`, `ClaudeService` registered on `app` via service locator pattern

## Key Domain Concepts

- **Session** — Parliamentary session period
- **Geschaeft** — Parliamentary business item/legislation
- **Parlamentarier** — Member of parliament, with political positioning scores on 7 axes (left-right, conservative-liberal, free market, innovation, energy independence, resilience, lean government)
- **Wortmeldung** — Parliamentary speech/statement (HTML text)
- **Abstimmung/Stimmabgabe** — Vote and individual vote cast (1=yes, 2=no, 3=abstain, 4=absent, 5=excused, 6=president)
- **Proposition** — AI-extracted key messages from speeches

## Dependencies

- **App:** SwiftUI, SwiftData (no external package dependencies)
- **Server:** Vapor 4.99+, Fluent 4.11+, FluentPostgresDriver 2.9+, Leaf 4.4+ (SPM managed)
- **Infrastructure:** PostgreSQL 16 (via Docker Compose)

## Score Package — Shared Base Classes

The [Score](../score) package (`import Score` / `import ScoreUI`) is a shared local SPM library providing financial and utility base types used across sibling projects. While this project does not currently depend on Score, the following types are available:

| Type | Module | Description |
|------|--------|-------------|
| `Money` | Score | Currency-safe monetary amounts with `Decimal` precision. Arithmetic enforces matching currencies. |
| `Currency` | Score | ISO 4217 enum with 180+ currencies, decimal places, and localized names. |
| `Percent` | Score | Percentage as factor (e.g. `0.10` = 10%). |
| `FXRate` | Score | Bid/ask exchange rates with conversion methods. |
| `VATCalculation` | Score | VAT split (net/gross) with inclusive/exclusive handling. |
| `YearMonth` | Score | Year-month value type for monthly periods. |
| `DayCountRule` | Score | Financial day count conventions (ACT/360, ACT/365, 30/360). |
| `ServicePipeline` | Score | Async middleware chain for service operations. |
| `ServiceError` | Score | Typed errors (notFound, validation, businessRule, etc.). |
| `CSVExportable` | Score | Protocol for CSV row export. |
| `IBANValidator` | Score | ISO 13616 IBAN validation. |
| `SCORReferenceGenerator` | Score | ISO 11649 creditor reference with Mod 97. |
| `ErrorHandler` | ScoreUI | Observable error state management for SwiftUI. |
| `PDFRenderer` | ScoreUI | UIKit-based PDF generation. |
| `.errorAlert()` | ScoreUI | SwiftUI modifier for error alert presentation. |

To add Score as a dependency, add a local package reference to `../score` in Xcode.
