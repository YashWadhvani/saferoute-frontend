// NOTE: this file used to contain a second ApiClient implementation.
// The project has been consolidated to use the single core client
// located at `lib/core/api_client.dart` (ApiClient.dio).
//
// This file now re-exports the core API for backward compatibility.
// Prefer importing '../core/api_client.dart' directly going forward.

export '../core/api_client.dart';

// If you still see references to ApiClient.create() or the old instance
// based ApiClient in the codebase, please update them to use
// `ApiClient.dio` (the shared Dio instance) or refactor services to use
// the service classes which internally use the shared client.
