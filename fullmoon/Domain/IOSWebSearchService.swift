//
//  IOSWebSearchService.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN on 05/11/2026.
//

#if os(iOS)
import Foundation
import Noctis
import Python
import os

final class IOSWebSearchService: WebSearchService, @unchecked Sendable {
    static let shared = IOSWebSearchService()
    private static let logger = Logger(subsystem: "com.sebastiendaguin.NoctisAi", category: "WebSearch")

    // CPython is process-wide. Only this queue owns its objects and initializes the interpreter.
    private let queue = DispatchQueue(label: "com.sebastiendaguin.NoctisAi.SearXNG", qos: .utility)
    private var globals: UnsafeMutablePointer<PyObject>?

    private init() {}

    func search(query: String) async throws -> [SearchResult] {
        try Task.checkCancellation()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.count <= 300, query.utf8.count <= 1_200,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            Self.logFailure(stage: .validateQuery, category: .invalidQuery)
            throw SearchError.invalidQuery
        }
        let state = OSAllocatedUnfairLock(initialState: (
            cancelled: false, continuation: Optional<CheckedContinuation<[SearchResult], any Error>>.none
        ))
        let results = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SearchResult], any Error>) in
                let cancelled = state.withLock { state in
                    if state.cancelled { return true }
                    state.continuation = continuation
                    return false
                }
                guard !cancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                queue.async {
                    guard !state.withLock({ $0.cancelled }) else { return }
                    let result = Result { try self.performSearch(query) }
                    let continuation = state.withLock { state in
                        defer { state.continuation = nil }
                        return state.continuation
                    }
                    continuation?.resume(with: result)
                }
            }
        } onCancel: {
            // A running Python call finishes on its queue; the cancelled caller resumes immediately.
            let continuation = state.withLock { state in
                state.cancelled = true
                defer { state.continuation = nil }
                return state.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
        return results
    }

    private func performSearch(_ query: String) throws -> [SearchResult] {
        Self.logStage(.searchRequested)
        if globals == nil { try initialize() }
        let gil = PyGILState_Ensure()
        defer { PyGILState_Release(gil) }
        guard let globals,
              let function = PyDict_GetItemString(globals, "search"),
              let arguments = PyTuple_New(2) else { throw pythonError(stage: .prepareSearch) }
        defer { Py_DecRef(arguments) }
        let cache: String
        do {
            cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
                .appendingPathComponent("SearXNG", isDirectory: true).path
        } catch {
            Self.logFailure(stage: .cacheDirectory, category: .fileSystem)
            throw error
        }
        guard let text = PyUnicode_FromString(query), let directory = PyUnicode_FromString(cache) else {
            throw pythonError(stage: .prepareSearch)
        }
        // PyTuple_SetItem transfers ownership of both Python strings to the tuple.
        guard PyTuple_SetItem(arguments, 0, text) == 0,
              PyTuple_SetItem(arguments, 1, directory) == 0 else { throw pythonError(stage: .prepareSearch) }
        Self.logStage(.searchStarted)
        guard let result = PyObject_CallObject(function, arguments) else { throw pythonError(stage: .executeSearch) }
        defer { Py_DecRef(result) }
        var count = 0
        guard let bytes = PyUnicode_AsUTF8AndSize(result, &count) else {
            throw pythonError(stage: .encodeResponse)
        }
        guard count <= 2 * 1_024 * 1_024 else {
            PyErr_Clear()
            Self.logFailure(stage: .encodeResponse, category: .responseTooLarge)
            throw SearchError.searchFailed
        }
        struct Response: Decodable { let results: [SearchResult] }
        let results: [SearchResult]
        do {
            results = try JSONDecoder().decode(Response.self, from: Data(bytes: bytes, count: count)).results
        } catch {
            Self.logFailure(stage: .decodeResponse, category: .invalidResponse)
            throw error
        }
        Self.logStage(.searchCompleted)
        return results
    }

    private func initialize() throws {
        Self.logStage(.runtimeInitializing)
        guard let resources = Bundle.main.resourceURL,
              let scriptURL = Bundle.main.url(forResource: "ios_searxng", withExtension: "py", subdirectory: "SearXNG") else {
            throw runtimeError(stage: .resources)
        }
        if Py_IsInitialized() == 0 {
            var preconfig = PyPreConfig()
            PyPreConfig_InitIsolatedConfig(&preconfig)
            preconfig.utf8_mode = 1
            guard PyStatus_Exception(Py_PreInitialize(&preconfig)) == 0 else {
                throw runtimeError(stage: .pythonPreinitialize)
            }
            var config = PyConfig()
            PyConfig_InitIsolatedConfig(&config)
            defer { PyConfig_Clear(&config) }
            config.write_bytecode = 0
            config.install_signal_handlers = 0
            config.buffered_stdio = 0
            config.module_search_paths_set = 1
            config.home = Py_DecodeLocale(resources.appendingPathComponent("python").path, nil)
            config.executable = Py_DecodeLocale(Bundle.main.executableURL?.path ?? "", nil)
            guard config.home != nil, config.executable != nil else { throw runtimeError(stage: .pythonConfiguration) }
            for path in ["python/lib/python3.13", "python/lib/python3.13/lib-dynload", "SearXNG/app_packages"] {
                guard let wide = Py_DecodeLocale(resources.appendingPathComponent(path).path, nil) else {
                    throw runtimeError(stage: .pythonConfiguration)
                }
                defer { PyMem_RawFree(wide) }
                guard PyStatus_Exception(PyWideStringList_Append(&config.module_search_paths, wide)) == 0 else {
                    throw runtimeError(stage: .pythonConfiguration)
                }
            }
            guard PyStatus_Exception(Py_InitializeFromConfig(&config)) == 0 else {
                throw runtimeError(stage: .pythonInitialize)
            }
            PyEval_SaveThread()
        }
        Self.logStage(.pythonReady)
        try loadScript(at: scriptURL)
    }

    private func loadScript(at url: URL) throws {
        let gil = PyGILState_Ensure()
        defer { PyGILState_Release(gil) }
        let script: String
        do {
            script = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logFailure(stage: .loadScript, category: .fileSystem)
            throw error
        }
        guard let dictionary = PyDict_New() else { throw pythonError(stage: .loadScript) }
        guard let result = PyRun_StringFlags(script, Py_file_input, dictionary, dictionary, nil) else {
            Py_DecRef(dictionary)
            throw pythonError(stage: .loadScript)
        }
        Py_DecRef(result)
        globals = dictionary
        Self.logStage(.scriptReady)
    }

    private func runtimeError(stage: DiagnosticStage) -> SearchError {
        Self.logFailure(stage: stage, category: .runtimeUnavailable)
        return .runtimeUnavailable
    }

    private func pythonError(stage: DiagnosticStage) -> SearchError {
        let category = Self.pythonCategory()
        PyErr_Clear()
        Self.logFailure(stage: stage, category: category)
        return .searchFailed
    }

    // Called only while holding the GIL. Never inspect exception messages or tracebacks.
    private static func pythonCategory() -> DiagnosticCategory {
        guard PyErr_Occurred() != nil else { return .pythonNoException }
        if PyErr_ExceptionMatches(PyExc_ImportError) != 0 { return .pythonImport }
        if PyErr_ExceptionMatches(PyExc_OSError) != 0 { return .pythonOS }
        if PyErr_ExceptionMatches(PyExc_UnicodeError) != 0 { return .pythonUnicode }
        if PyErr_ExceptionMatches(PyExc_ValueError) != 0 { return .pythonValue }
        if PyErr_ExceptionMatches(PyExc_TypeError) != 0 { return .pythonType }
        if PyErr_ExceptionMatches(PyExc_KeyError) != 0 { return .pythonKey }
        if PyErr_ExceptionMatches(PyExc_MemoryError) != 0 { return .pythonMemory }
        if PyErr_ExceptionMatches(PyExc_RuntimeError) != 0 { return .pythonRuntime }
        return .pythonOther
    }

    private static func logStage(_ stage: DiagnosticStage) {
        logger.info("stage=\(stage.rawValue, privacy: .public)")
    }

    private static func logFailure(stage: DiagnosticStage, category: DiagnosticCategory) {
        logger.error("stage=\(stage.rawValue, privacy: .public) category=\(category.rawValue, privacy: .public)")
    }

    // Only these fixed identifiers can enter diagnostic logs, never user or runtime strings.
    private enum DiagnosticStage: String {
        case validateQuery = "validate_query"
        case searchRequested = "search_requested"
        case runtimeInitializing = "runtime_initializing"
        case resources
        case pythonPreinitialize = "python_preinitialize"
        case pythonConfiguration = "python_configuration"
        case pythonInitialize = "python_initialize"
        case pythonReady = "python_ready"
        case loadScript = "load_script"
        case scriptReady = "script_ready"
        case prepareSearch = "prepare_search"
        case cacheDirectory = "cache_directory"
        case searchStarted = "search_started"
        case executeSearch = "execute_search"
        case encodeResponse = "encode_response"
        case decodeResponse = "decode_response"
        case searchCompleted = "search_completed"
    }

    private enum DiagnosticCategory: String {
        case invalidQuery = "invalid_query"
        case runtimeUnavailable = "runtime_unavailable"
        case fileSystem = "file_system"
        case invalidResponse = "invalid_response"
        case responseTooLarge = "response_too_large"
        case pythonNoException = "python_no_exception"
        case pythonImport = "ImportError"
        case pythonOS = "OSError"
        case pythonUnicode = "UnicodeError"
        case pythonValue = "ValueError"
        case pythonType = "TypeError"
        case pythonKey = "KeyError"
        case pythonMemory = "MemoryError"
        case pythonRuntime = "RuntimeError"
        case pythonOther = "python_other"
    }

    private enum SearchError: LocalizedError {
        case invalidQuery, runtimeUnavailable, searchFailed

        var errorDescription: String? {
            switch self {
            case .invalidQuery: String(localized: "web_search.error.invalid_query")
            case .runtimeUnavailable: String(localized: "web_search.error.runtime_unavailable")
            case .searchFailed: String(localized: "web_search.error.search_failed")
            }
        }
    }
}
#endif
